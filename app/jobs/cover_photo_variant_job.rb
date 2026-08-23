class CoverPhotoVariantJob < ApplicationJob
  queue_as :default

  def perform(trip_id)
    trip = Trip.find_by(id: trip_id)
    return unless trip&.cover_photo&.attached?

    trip.cover_photo.variant(:thumb).processed
  rescue ActiveStorage::InvariableError => e
    Rails.logger.warn("CoverPhotoVariantJob: could not process trip #{trip_id} cover photo: #{e.message}")
  end
end
