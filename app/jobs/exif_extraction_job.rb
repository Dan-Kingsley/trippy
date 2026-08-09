require "exif"

class ExifExtractionJob < ApplicationJob
  queue_as :default

  def perform(photo_id)
    photo = Photo.find_by(id: photo_id)
    return unless photo&.image&.attached?

    photo.image.blob.open do |file|
      data = Exif::Data.new(file)

      if (lat = decimal_degrees(data.gps_latitude, data.gps_latitude_ref))
        photo.latitude = lat
        photo.longitude = decimal_degrees(data.gps_longitude, data.gps_longitude_ref)
      end

      if data.date_time_original.present?
        photo.taken_at = Time.strptime(data.date_time_original, "%Y:%m:%d %H:%M:%S")
      end
    end

    photo.save! if photo.changed?
  rescue Exif::NotReadable, Exif::Error, ArgumentError
    # No (usable) EXIF data in this file - leave coordinates/time for manual entry.
  ensure
    photo&.trip_entry&.recompute_from_photos!
  end

  private
    def decimal_degrees(dms, ref)
      return nil unless dms && ref

      degrees = dms[0].to_f + (dms[1].to_f / 60) + (dms[2].to_f / 3600)
      %w[S W].include?(ref.to_s.upcase) ? -degrees : degrees
    end
end
