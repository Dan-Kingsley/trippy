class Photo < ApplicationRecord
  belongs_to :trip_entry
  belongs_to :uploaded_by, class_name: "User", optional: true

  has_one_attached :image do |attachable|
    # Shown everywhere a photo appears inline (carousel, feeds, etc.) -
    # kept small so pages stay snappy. Only the lightbox loads :full.
    # These only apply to image content; videos are previewed instead (see
    # PhotoVariantJob).
    # fail_on: :none, unlimited: true - confirmed against a real Pixel 9 Pro
    # photo (6144x8160, ~50MP): the file is completely valid end to end (an
    # independent decoder reads every row of it fine) - what actually stops
    # libjpeg partway through, reporting "premature end of JPEG image", is
    # libjpeg-turbo/libvips' own built-in denial-of-service guard against
    # decompression bombs, which a real, legitimately huge camera sensor
    # image is large enough to trip as a false positive. `unlimited: true`
    # is libvips' documented escape hatch for exactly this ("remove all
    # denial of service limits"); fail_on: :none is still needed alongside
    # it since without it libvips would otherwise raise loudly on this same
    # now-tolerated condition rather than decoding cleanly. Since this
    # removes a real protection against maliciously crafted tiny-file/huge-
    # dimension JPEG bombs, PhotoVariantJob re-imposes an explicit megapixel
    # cap of our own choosing before ever reaching this loader, rather than
    # trusting libvips' undocumented/miscalibrated internal threshold.
    #
    # A dropped network transfer can't reach this code with fewer bytes than
    # the adventurer's browser actually sent - direct upload verifies a
    # checksum against the whole file server-side before the blob is ever
    # usable (see photo_date_controller.js). But that checksum is computed
    # from whatever bytes the browser itself read off the source file, so it
    # can't catch a source file that was already incomplete before the
    # browser ever touched it - e.g. a cloud photo library (iCloud/Google
    # Photos "optimise storage") handing over a not-yet-fully-downloaded
    # original. That's a genuinely truncated JPEG, not a false-positive guard
    # trip, and no loader option here can recover data that was never
    # uploaded - acceptable_jpeg_completeness below rejects it synchronously,
    # up front, rather than letting fail_on: :none quietly bake a
    # partial/blank-bottomed image into the :thumb/:full variants for
    # PhotoVariantJob's check_for_incomplete_decode to only notice later.
    attachable.variant :thumb, resize_to_limit: [ 900, 900 ], saver: { quality: 75 }, loader: { fail_on: :none, unlimited: true }
    attachable.variant :full, resize_to_limit: [ 3000, 3000 ], saver: { quality: 90 }, loader: { fail_on: :none, unlimited: true }
  end

  validate :acceptable_content_type
  validate :acceptable_jpeg_completeness

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

    # A JPEG stream always ends with an FFD9 (End Of Image) marker - a file
    # missing that in its last two bytes was cut short somewhere between the
    # camera/photo library and here (see Photo#image's comment on why the
    # direct-upload checksum can't catch this). Checking those two bytes is
    # enough to catch it and reject the upload synchronously, before
    # PhotoVariantJob ever gets a chance to quietly bake the missing tail
    # into a persisted :thumb/:full variant. Scoped to JPEG since that's the
    # only format here with such a simple, fixed trailer to check - PNG/WebP/
    # HEIC would each need their own container-specific check.
    def acceptable_jpeg_completeness
      return unless image.attached?
      return unless image.content_type == "image/jpeg"
      return if image.byte_size.to_i < 2

      trailer = image.download_chunk((image.byte_size - 2)...image.byte_size)
      errors.add(:image, :incomplete_upload) unless trailer == "\xFF\xD9".b
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
