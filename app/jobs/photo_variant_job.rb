class PhotoVariantJob < ApplicationJob
  queue_as :default

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
    # silently missing an entry) but don't retry forever; the view falls
    # back to a placeholder when no processed variant is available.
    Rails.logger.warn("PhotoVariantJob: could not process photo #{photo_id}: #{e.message}")
  end
end
