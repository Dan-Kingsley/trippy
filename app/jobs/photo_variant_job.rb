class PhotoVariantJob < ApplicationJob
  queue_as :default

  # A truncated/corrupt decode (fail_on: :truncated on the variant's loader,
  # set on Photo#image) raises Vips::Error rather than returning a bad image - retry
  # a couple of times in case it's transient container memory pressure before
  # giving up and flagging the photo as failed. The give-up block is passed
  # directly to retry_on (rather than a separate discard_on for the same
  # exception, which would ambiguously double-register a handler for it).
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
    end
  rescue ActiveStorage::InvariableError, ActiveStorage::UnpreviewableError, ActiveStorage::UnrepresentableError => e
    # A corrupt/truncated upload or an unsupported codec can't be turned into
    # a variant/preview - leave the photo attached (so the uploader isn't
    # silently missing an entry) but don't retry forever; flag it so the
    # uploader gets a visible signal instead of a permanently-broken thumbnail.
    photo.update_columns(processing_failed_at: Time.current, processing_error: PhotoVariantJob.sanitize_error_message(e.message))
    Rails.logger.warn("PhotoVariantJob: could not process photo #{photo_id}: #{e.message}")
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
