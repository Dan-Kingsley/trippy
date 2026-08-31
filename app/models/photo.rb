class Photo < ApplicationRecord
  belongs_to :trip_entry
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_one_attached :image do |attachable|
    # Shown everywhere a photo appears inline (carousel, feeds, etc.) -
    # kept small so pages stay snappy. Only the lightbox loads :full.
    # These only apply to image content; videos are previewed instead (see
    # PhotoVariantJob).
    # fail_on: :none - deliberately the most permissive libvips level. Some
    # Pixel photos' entropy-coded scan data runs out before every scanline
    # the file's own header promises has been decoded, which libjpeg reports
    # as "premature end of JPEG image" - libvips classifies that as
    # *truncated*, not merely :error, so :truncated (tried first) still
    # rejected these exactly like :error did. Under :none this no longer
    # raises - it decodes what it can and leaves the remaining rows
    # undrawn, which is *also* not fully right (see
    # PhotoVariantJob#check_for_incomplete_decode for how a resulting
    # partial image gets flagged rather than passed off as a clean one). A
    # *dropped/incomplete upload transfer*, the original motivation for
    # failing loudly here, can no longer reach this code with fewer bytes
    # than the adventurer actually sent regardless of this setting: direct
    # upload verifies a checksum against the whole file server-side before
    # the blob is ever usable (see photo_date_controller.js). What :none
    # still can't paper over is a file libvips can't make any sense of at
    # all - PhotoVariantJob's rescue/retry/flag path remains the backstop
    # for that.
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

  # True when a thumb/full variant exists but was decoded from a source
  # image libvips only got partway through (see Photo#image's fail_on:
  # :none) - the photo is visible, just potentially missing its bottom rows.
  def processing_incomplete?
    processing_incomplete_at.present?
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
