module PhotoUploadable
  extend ActiveSupport::Concern

  private
    # Attaches every selected file (the plain multipart fallback) and direct
    # upload signed ID (the normal JS-driven path) to the entry as a new
    # Photo, in the order they were selected. Returns the validation error
    # message for each rejected upload (e.g. unsupported content type, or
    # Photo#acceptable_jpeg_completeness's real-decode check failing) rather
    # than just a count, so the caller can tell the adventurer *why* -
    # otherwise a rejection is a dead end with no way to tell a genuinely
    # incomplete file apart from some other rare failure mode.
    def attach_uploads(entry)
      uploads = Array(params[:photos]) + Array(params[:photo_signed_ids])
      rejection_reasons = []

      uploads.each_with_index do |upload, index|
        next if upload.blank?
        photo = entry.photos.create(uploaded_by: Current.user, position: entry.photos.count + index, image: upload)
        rejection_reasons << photo.errors[:image].first unless photo.persisted?
      end

      rejection_reasons
    end
end
