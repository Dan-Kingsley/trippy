class Photo < ApplicationRecord
  belongs_to :trip_entry
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_one_attached :image do |attachable|
    # Shown everywhere a photo appears inline (carousel, feeds, etc.) -
    # kept small so pages stay snappy. Only the lightbox loads :full.
    # These only apply to image content; videos are previewed instead (see
    # PhotoVariantJob).
    # fail_on: :truncated makes a genuinely incomplete/corrupt decode raise
    # instead of silently returning a gray-filled image - see PhotoVariantJob
    # for how that's turned into a retry + failure flag. Deliberately not the
    # stricter :error: some phone cameras (e.g. Pixel's Ultra HDR JPEGs, which
    # append a second gain-map image via a Multi-Picture Format trailer) emit
    # a recoverable decode error on that trailing data even though the actual
    # photo pixels decoded fine - :error treated that the same as real
    # corruption, flagging every one of those photos as failed to process.
    attachable.variant :thumb, resize_to_limit: [ 900, 900 ], saver: { quality: 75 }, loader: { fail_on: :truncated }
    attachable.variant :full, resize_to_limit: [ 3000, 3000 ], saver: { quality: 90 }, loader: { fail_on: :truncated }
  end

  validate :acceptable_content_type

  after_create_commit :extract_exif_later
  after_create_commit :prewarm_variants_later
  after_destroy_commit :recompute_entry_later

  def video?
    image.attached? && image.content_type.start_with?("video/")
  end

  def processing_failed?
    processing_failed_at.present?
  end

  private
    def acceptable_content_type
      return unless image.attached?
      return if image.content_type.in?(MediaContentTypes::ALL)

      errors.add(:image, :invalid_content_type)
    end

    def extract_exif_later
      ExifExtractionJob.perform_later(id) unless video?
    end

    def prewarm_variants_later
      PhotoVariantJob.perform_later(id)
    end

    def recompute_entry_later
      trip_entry.recompute_from_photos!
    end
end
