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
    # A genuinely truncated/corrupt upload can't be reliably told apart from
    # a fine one synchronously at upload time - a real-decode check was tried
    # here and repeatedly produced false positives of its own (see git log
    # for the saga), and running it synchronously in the request thread turns
    # out to race PhotoVariantJob's own decodes running on Solid Queue's
    # in-Puma worker threads (see config/puma.rb's SOLID_QUEUE_IN_PUMA),
    # since libvips' error-message buffer is a process-global static, not
    # thread-local. Immich (a much larger, more battle-tested photo app built
    # on the same sharp/libvips foundation) doesn't attempt this either -
    # their strict decode only runs at thumbnail time, after the upload is
    # already accepted, and a failure there is just logged, not surfaced as a
    # rejected upload. Following that precedent: never reject an upload for
    # looking incomplete - accept it, and let PhotoVariantJob's
    # check_for_incomplete_decode flag it after the fact (processing_failed?/
    # processing_incomplete?, surfaced via the warning badge on the edit page
    # and carousel) rather than trying to definitively rule on it up front.
    attachable.variant :thumb, resize_to_limit: [ 900, 900 ], saver: { quality: 75 }, loader: { fail_on: :none, unlimited: true }
    attachable.variant :full, resize_to_limit: [ 3000, 3000 ], saver: { quality: 90 }, loader: { fail_on: :none, unlimited: true }
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
