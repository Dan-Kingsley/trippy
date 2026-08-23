module PhotoUploadable
  extend ActiveSupport::Concern

  private
    # Attaches every selected file (the plain multipart fallback) and direct
    # upload signed ID (the normal JS-driven path) to the entry as a new
    # Photo, in the order they were selected. Returns how many were rejected
    # for having an unsupported content type, so the caller can let the user
    # know some of what they picked wasn't attached.
    def attach_uploads(entry)
      uploads = Array(params[:photos]) + Array(params[:photo_signed_ids])
      rejected = 0

      uploads.each_with_index do |upload, index|
        next if upload.blank?
        photo = entry.photos.create(uploaded_by: Current.user, position: entry.photos.count + index, image: upload)
        rejected += 1 unless photo.persisted?
      end

      rejected
    end
end
