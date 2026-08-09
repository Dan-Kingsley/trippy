class Photo < ApplicationRecord
  belongs_to :trip_entry
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_one_attached :image

  after_create_commit :extract_exif_later
  after_destroy_commit :recompute_entry_later

  private
    def extract_exif_later
      ExifExtractionJob.perform_later(id)
    end

    def recompute_entry_later
      trip_entry.recompute_from_photos!
    end
end
