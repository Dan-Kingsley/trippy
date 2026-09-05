class PhotoVariantJob < ApplicationJob
  queue_as :default

  # Comfortably above real camera sensors we expect to see (Pixel 9 Pro's
  # main sensor is ~50MP) while still bounding the memory a single decode
  # can demand now that Photo#image's `unlimited: true` has removed
  # libvips' own (apparently miscalibrated-for-real-photos) guard against
  # decompression-bomb JPEGs - see reject_if_oversized.
  MAX_MEGAPIXELS = 120

  class ImageTooLargeError < StandardError; end

  # Even fail_on: :none (see Photo#image) still raises Vips::Error for a file
  # libvips can't make any sense of at all (not just a decode warning/error
  # on an otherwise-recognized structure) - retry a couple of times in case
  # it's transient container memory pressure before giving up and flagging
  # the photo as failed. The give-up block is passed directly to retry_on
  # (rather than a separate discard_on for the same exception, which would
  # ambiguously double-register a handler for it).
  retry_on Vips::Error, wait: :polynomially_longer, attempts: 3 do |job, error|
    photo_id = job.arguments.first
    Photo.find_by(id: photo_id)&.update_columns(processing_failed_at: Time.current, processing_error: PhotoVariantJob.sanitize_error_message(error.message))
    Rails.logger.warn("PhotoVariantJob: giving up on photo #{photo_id} after retries: #{error.message}")
  end

  def perform(photo_id)
    photo = Photo.find_by(id: photo_id)
    return unless photo&.image&.attached?

    if photo.video?
      # Prewarms a poster-frame image (via ffmpeg) used as the video's
      # thumbnail in the carousel, in place of the :thumb/:full image variants.
      photo.image.preview(resize_to_limit: [ 900, 900 ]).processed
    else
      reject_if_oversized(photo)
      photo.image.variant(:thumb).processed
      photo.image.variant(:full).processed
      check_for_incomplete_decode(photo)
    end
  rescue ActiveStorage::InvariableError, ActiveStorage::UnpreviewableError, ActiveStorage::UnrepresentableError, ImageTooLargeError => e
    # A corrupt/truncated upload, an unsupported codec, or (see
    # reject_if_oversized) an implausibly huge image can't be turned into a
    # variant/preview - leave the photo attached (so the uploader isn't
    # silently missing an entry) but don't retry forever; flag it so the
    # uploader gets a visible signal instead of a permanently-broken thumbnail.
    photo.update_columns(processing_failed_at: Time.current, processing_error: PhotoVariantJob.sanitize_error_message(e.message))
    Rails.logger.warn("PhotoVariantJob: could not process photo #{photo_id}: #{e.message}")
  end

  private
    # Photo#image's loader runs with unlimited: true, which removes
    # libvips' own built-in guard against decompression-bomb JPEGs (a small
    # file claiming implausibly huge dimensions) because that guard was also
    # rejecting genuine, huge camera-sensor photos as false positives. This
    # reimposes an explicit limit of our own before any decoding happens, so
    # dropping libvips' guard doesn't just leave the door open. Only reads
    # the header (cheap - libvips doesn't decode pixels until something
    # demands them), so this doesn't itself pay the cost it's guarding
    # against.
    def reject_if_oversized(photo)
      photo.image.blob.open do |file|
        header = Vips::Image.new_from_file(file.path, access: :sequential)
        megapixels = header.width.to_f * header.height / 1_000_000.0
        if megapixels > MAX_MEGAPIXELS
          raise ImageTooLargeError, "image is #{megapixels.round}MP (#{header.width}x#{header.height}), over the #{MAX_MEGAPIXELS}MP limit"
        end
      end
    end

    # fail_on: :none (see Photo#image) means the variants above can succeed
    # having only decoded *part* of the source image, silently - libvips
    # doesn't expose "I stopped early" as a flag on the image it hands back,
    # so the only reliable way to tell a fully-decoded photo from a
    # partially-decoded one is to redo the decode at the strictest fail_on
    # level and see whether *that* raises. unlimited: true carries over here
    # too - without it, this would flag every oversized-but-legitimate photo
    # as "incomplete" purely from re-tripping the same guard reject_if_oversized
    # already made a considered decision about above. This throwaway
    # re-decode exists purely to surface that error; its pixels are never
    # used, and its cost (one extra full decode pass) only applies to photos
    # that already made it past the real rescue above.
    def check_for_incomplete_decode(photo)
      # The :thumb/:full decodes above run with fail_on: :none, so any
      # warnings libvips logged for them (e.g. the same "premature end of
      # JPEG file" this re-decode is about to check for) are still sitting in
      # libvips' error buffer - it's only ever drained when a Vips::Error is
      # actually raised/constructed. Left alone, this decode's own error
      # would be built from that stale backlog plus its own warning, showing
      # the same line duplicated once per earlier decode that hit it. Clearing
      # first ensures the message below reflects only this decode.
      Vips.vips_error_clear
      photo.image.blob.open do |file|
        Vips::Image.new_from_file(file.path, fail_on: :error, unlimited: true, access: :sequential).avg
      end
    rescue Vips::Error => e
      photo.update_columns(processing_incomplete_at: Time.current, processing_error: PhotoVariantJob.sanitize_error_message(e.message))
      Rails.logger.warn("PhotoVariantJob: photo #{photo.id} only partially decoded: #{e.message}")
    end

  # Strips absolute filesystem paths (the tmp path ActiveStorage extracted the
  # blob to, e.g. in a libvips "unable to load from file ..." message) before
  # this is ever shown to an adventurer via the processing-failed badge -
  # everything else about the underlying error is left intact since that's
  # the whole point of storing it.
  def self.sanitize_error_message(message)
    message.to_s.gsub(%r{/[\w.\-]+(?:/[\w.\-]+)+}, "<path>").truncate(500)
  end
end
