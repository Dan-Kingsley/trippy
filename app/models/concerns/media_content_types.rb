# Shared allowlist of attachment content types accepted anywhere in the app -
# both for direct user uploads (Photo) and archive imports
# (Importing::TripArchiveImporter) - so unsupported/corrupt files are
# rejected up front instead of silently attaching something that can never
# be turned into a variant.
module MediaContentTypes
  IMAGES = %w[ image/jpeg image/png image/webp image/heic image/heif ]
  VIDEOS = %w[ video/mp4 video/quicktime video/webm ]
  ALL = IMAGES + VIDEOS
end
