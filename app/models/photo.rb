class Photo < ApplicationRecord
  belongs_to :trip_entry
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_one_attached :image do |attachable|
    # Shown everywhere a photo appears inline (carousel, feeds, etc.) -
    # kept small so pages stay snappy. Only the lightbox loads :full.
    # These only apply to image content; videos are previewed instead (see
    # PhotoVariantJob).
    # fail_on: :none - deliberately the most permissive libvips level. Pixel's
    # Ultra HDR JPEGs (a second gain-map image appended after the primary
    # one) reliably decode with a "VipsJpeg: premature end of JPEG image"
    # condition that libvips classifies as *truncated*, not merely :error -
    # so :truncated (tried first) still rejected every one of these photos as
    # if they were corrupt uploads, identically to :error. There's no tier
    # between "reject this" and "never reject on a decode warning/error" that
    # would let this specific, real, camera-produced structure through while
    # still catching truncation - and a *dropped/incomplete upload transfer*
    # (the original motivation for failing loudly here) can no longer reach
    # this code with fewer bytes than the adventurer actually sent: direct
    # upload verifies a checksum against the whole file server-side before
    # the blob is ever usable (see photo_date_controller.js), independent of
    # this loader setting. What :none still can't paper over is a file that
    # was *always* malformed (e.g. someone's already-corrupt photo) -
    # PhotoVariantJob's rescue/retry/flag path remains the backstop for that.
    attachable.variant :thumb, resize_to_limit: [ 900, 900 ], saver: { quality: 75 }, loader: { fail_on: :none }
    attachable.variant :full, resize_to_limit: [ 3000, 3000 ], saver: { quality: 90 }, loader: { fail_on: :none }
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
