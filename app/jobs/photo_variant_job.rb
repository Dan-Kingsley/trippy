class PhotoVariantJob < ApplicationJob
  queue_as :default

  def perform(photo_id)
    photo = Photo.find_by(id: photo_id)
    return unless photo&.image&.attached?

    photo.image.variant(:thumb).processed
    photo.image.variant(:full).processed
  end
end
