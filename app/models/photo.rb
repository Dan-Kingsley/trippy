class Photo < ApplicationRecord
  belongs_to :trip_entry
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_one_attached :image do |attachable|
    # Shown everywhere a photo appears inline (carousel, feeds, etc.) -
    # kept small so pages stay snappy. Only the lightbox loads :full.
    attachable.variant :thumb, resize_to_limit: [ 900, 900 ], saver: { quality: 75 }
    attachable.variant :full, resize_to_limit: [ 3000, 3000 ], saver: { quality: 90 }
  end

  after_create_commit :extract_exif_later
  after_create_commit :prewarm_variants_later
  after_destroy_commit :recompute_entry_later

  private
    def extract_exif_later
      ExifExtractionJob.perform_later(id)
    end

    def prewarm_variants_later
      PhotoVariantJob.perform_later(id)
    end

    def recompute_entry_later
      trip_entry.recompute_from_photos!
    end
end
