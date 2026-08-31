class PhotoVariantJob < ApplicationJob
  queue_as :default

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
      photo.image.variant(:thumb).processed
      photo.image.variant(:full).processed
      check_for_incomplete_decode(photo)
    end
  rescue ActiveStorage::InvariableError, ActiveStorage::UnpreviewableError, ActiveStorage::UnrepresentableError => e
    # A corrupt/truncated upload or an unsupported codec can't be turned into
    # a variant/preview - leave the photo attached (so the uploader isn't
    # silently missing an entry) but don't retry forever; flag it so the
    # uploader gets a visible signal instead of a permanently-broken thumbnail.
    photo.update_columns(processing_failed_at: Time.current, processing_error: PhotoVariantJob.sanitize_error_message(e.message))
    Rails.logger.warn("PhotoVariantJob: could not process photo #{photo_id}: #{e.message}")
  end

  private
    # fail_on: :none (see Photo#image) means the variants above can succeed
    # having only decoded *part* of the source image, silently - libvips
    # doesn't expose "I stopped early" as a flag on the image it hands back,
    # so the only reliable way to tell a fully-decoded photo from a
    # partially-decoded one is to redo the decode at the strictest fail_on
    # level and see whether *that* raises. This throwaway re-decode exists
    # purely to surface that error; its pixels are never used, and its cost
    # (one extra full decode pass) only applies to photos that already made
    # it past the real rescue above.
    def check_for_incomplete_decode(photo)
      photo.image.blob.open do |file|
        Vips::Image.new_from_file(file.path, fail_on: :error, access: :sequential).avg
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
