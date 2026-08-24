require "exif"

class ExifExtractionJob < ApplicationJob
  queue_as :default

  # Guards against transient issues (e.g. the blob's storage momentarily
  # unavailable under concurrent load) - a permanent parse failure is
  # swallowed below, not raised, so this only ever fires for genuine
  # infrastructure hiccups.
  retry_on StandardError, attempts: 2, wait: 5.seconds

  def perform(photo_id)
    photo = Photo.find_by(id: photo_id)
    return unless photo&.image&.attached?

    photo.image.blob.open do |file|
      found_gps = extract_with_exif_gem(photo, file)
      extract_gps_with_vips(photo, file.path) unless found_gps
    end

    photo.save! if photo.changed?
  ensure
    photo&.trip_entry&.recompute_from_photos!
  end

  private
    # The primary extraction path: a small pure-Ruby EXIF/TIFF parser. Fast,
    # but less battle-tested against real-world camera quirks than libexif -
    # see extract_gps_with_vips for the fallback this feeds into.
    def extract_with_exif_gem(photo, file)
      data = Exif::Data.new(file)
      found = false

      if (lat = decimal_degrees(data.gps_latitude, data.gps_latitude_ref))
        photo.latitude = lat
        photo.longitude = decimal_degrees(data.gps_longitude, data.gps_longitude_ref)
        found = true
      end

      if data.date_time_original.present?
        photo.taken_at = Time.strptime(data.date_time_original, "%Y:%m:%d %H:%M:%S")
      end

      Rails.logger.info("ExifExtractionJob: exif gem #{found ? "found" : "found no"} GPS data for photo #{photo.id}")
      found
    rescue Exif::NotReadable, Exif::Error, ArgumentError => e
      Rails.logger.info("ExifExtractionJob: exif gem failed for photo #{photo.id}: #{e.message}")
      false
    end

    # Fallback GPS extraction via libvips/libexif, which tends to be more
    # robust against nonstandard camera JPEG structuring (e.g. Pixel Ultra
    # HDR's multi-picture format) than the small pure-Ruby exif gem. Only
    # runs when the primary path found nothing, so it never overrides a
    # successful exif-gem read.
    def extract_gps_with_vips(photo, path)
      image = Vips::Image.new_from_file(path, access: :sequential)
      fields = image.get_fields

      lat_field = fields.find { |f| f.include?("GPSLatitude") && !f.include?("Ref") }
      lat_ref_field = fields.find { |f| f.include?("GPSLatitudeRef") }
      lng_field = fields.find { |f| f.include?("GPSLongitude") && !f.include?("Ref") }
      lng_ref_field = fields.find { |f| f.include?("GPSLongitudeRef") }

      lat = vips_gps_decimal(image, lat_field, lat_ref_field)
      lng = vips_gps_decimal(image, lng_field, lng_ref_field)

      if lat && lng
        photo.latitude = lat
        photo.longitude = lng
        Rails.logger.info("ExifExtractionJob: vips fallback found GPS data for photo #{photo.id}")
      else
        Rails.logger.info("ExifExtractionJob: vips fallback found no GPS data for photo #{photo.id}")
        Rails.logger.debug { "ExifExtractionJob: vips EXIF fields for photo #{photo.id}: #{fields.grep(/exif/i)}" }
      end
    rescue Vips::Error => e
      Rails.logger.info("ExifExtractionJob: vips fallback failed for photo #{photo.id}: #{e.message}")
    end

    def vips_gps_decimal(image, field, ref_field)
      return nil unless field && ref_field

      dms = parse_vips_rational_triplet(image.get(field))
      ref = image.get(ref_field).to_s.strip
      return nil unless dms

      decimal_degrees(dms, ref)
    end

    # libvips/libexif may return a GPS coordinate as an array of [numerator,
    # denominator] rational pairs, or as a pre-formatted string like
    # "37/1, 25/1, 1200/100" - handle both shapes.
    def parse_vips_rational_triplet(raw)
      case raw
      when Array
        raw.first(3).map { |v| v.is_a?(Array) ? v[0].to_f / v[1].to_f : v.to_f }
      when String
        parts = raw.split(",").first(3)
        return nil if parts.size < 3
        parts.map { |part| Rational(part.strip).to_f rescue part.strip.to_f }
      end
    end

    def decimal_degrees(dms, ref)
      return nil unless dms && ref

      degrees = dms[0].to_f + (dms[1].to_f / 60) + (dms[2].to_f / 3600)
      %w[S W].include?(ref.to_s.upcase) ? -degrees : degrees
    end
end
