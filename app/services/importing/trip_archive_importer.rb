module Importing
  # Raised for whole-archive problems (unreadable zip, wrong/missing
  # manifest, size limits exceeded) - these abort the entire import before
  # any database writes happen. Problems scoped to a single trip inside an
  # otherwise-valid archive are recorded in Result#skipped_trips instead, so
  # one bad trip in a batch doesn't sink the rest.
  class InvalidManifestError < StandardError; end

  # Restores trips exported by Exporting::TripArchiveBuilder. See that class
  # for the authoritative manifest.json schema both sides agree on.
  class TripArchiveImporter
    FORMAT_VERSION = Exporting::TripArchiveBuilder::FORMAT_VERSION

    MAX_TOTAL_UNCOMPRESSED_BYTES = 2.gigabytes
    MAX_ENTRY_UNCOMPRESSED_BYTES = 100.megabytes
    MAX_COMPRESSION_RATIO = 100

    ALLOWED_IMAGE_CONTENT_TYPES = MediaContentTypes::IMAGES

    SAFE_ENTRY_NAME = %r{\A(manifest\.json|trips/\d+/(cover_photo\.[A-Za-z0-9]+|entries/\d+/photos/\d+\.[A-Za-z0-9]+))\z}

    Result = Struct.new(:imported, :overwritten, :skipped_trips, :warnings, keyword_init: true)

    def initialize(zip_path, importing_user:, conflict_policy:)
      @zip_path = zip_path
      @importing_user = importing_user
      @conflict_policy = conflict_policy.to_sym
      @warnings = []
      @user_cache = {}
    end

    def import!
      results = { imported: 0, overwritten: 0, skipped_trips: [] }

      Zip::File.open(@zip_path) do |zip|
        validate_archive!(zip)
        manifest = parse_manifest(zip)

        manifest.fetch("trips").each do |trip_data|
          begin
            outcome = import_trip!(zip, trip_data)
            results[outcome] += 1
          rescue => e
            results[:skipped_trips] << { title: trip_data["title"].to_s, reason: e.message }
            Rails.logger.error("[Importing::TripArchiveImporter] failed importing trip #{trip_data['title'].inspect}: #{e.class}: #{e.message}")
          end
        end
      end

      Result.new(**results, warnings: @warnings)
    rescue Zip::Error => e
      raise InvalidManifestError, "Couldn't read that file as a Trippy export (#{e.message})"
    end

    private
      # --- Archive-level validation (runs once, before any trip is touched) ---

      def validate_archive!(zip)
        total_uncompressed = 0

        zip.each do |entry|
          next unless entry.file?

          unless entry.name.match?(SAFE_ENTRY_NAME)
            raise InvalidManifestError, "Unexpected file in archive: #{entry.name}"
          end

          if entry.size > MAX_ENTRY_UNCOMPRESSED_BYTES
            raise InvalidManifestError, "#{entry.name} is too large"
          end

          if entry.compressed_size.positive? && (entry.size.to_f / entry.compressed_size) > MAX_COMPRESSION_RATIO
            raise InvalidManifestError, "#{entry.name} has a suspicious compression ratio"
          end

          total_uncompressed += entry.size
          if total_uncompressed > MAX_TOTAL_UNCOMPRESSED_BYTES
            raise InvalidManifestError, "Archive is too large"
          end
        end
      end

      def parse_manifest(zip)
        entry = zip.get_entry("manifest.json")
        manifest = JSON.parse(entry.get_input_stream.read)

        unless manifest["trippy_export_version"] == FORMAT_VERSION
          raise InvalidManifestError, "Unsupported export format"
        end
        unless manifest["trips"].is_a?(Array)
          raise InvalidManifestError, "Malformed manifest"
        end

        manifest
      rescue Errno::ENOENT
        raise InvalidManifestError, "Missing manifest.json"
      rescue JSON::ParserError
        raise InvalidManifestError, "manifest.json is not valid JSON"
      end

      # --- Per-trip import (each call is its own transaction; a failure here
      # is caught by the caller and recorded as a skipped trip) ---

      def import_trip!(zip, trip_data)
        secret_code = trip_data["secret_code"].presence
        existing = secret_code && @importing_user.owned_trips.find_by(secret_code: secret_code)

        if existing && @conflict_policy == :duplicate
          ActiveRecord::Base.transaction { create_trip!(zip, trip_data, secret_code: nil) }
          :imported
        elsif existing
          ActiveRecord::Base.transaction do
            existing.destroy!
            create_trip!(zip, trip_data, secret_code: secret_code)
          end
          :overwritten
        else
          ActiveRecord::Base.transaction { create_trip!(zip, trip_data, secret_code: secret_code) }
          :imported
        end
      end

      def create_trip!(zip, trip_data, secret_code:)
        trip = Trip.new(
          title: trip_data["title"].presence || "Imported trip",
          public: !!trip_data["public"],
          owner: @importing_user,
          secret_code: secret_code
        )

        begin
          trip.save!
        rescue ActiveRecord::RecordNotUnique
          # secret_code from the export collided with some other user's trip
          # (globally unique column) - vanishingly unlikely, but fall back to
          # minting a fresh identity for this one trip rather than failing it.
          trip.secret_code = nil
          trip.save!
        end

        attach_cover_photo!(zip, trip, trip_data["cover_photo"])
        add_collaborators!(trip, trip_data["collaborators"])
        Array(trip_data["entries"]).each { |entry_data| create_entry!(zip, trip, entry_data) }

        trip
      end

      def attach_cover_photo!(zip, trip, cover_photo_data)
        return if cover_photo_data.blank?

        bytes = read_zip_entry(zip, cover_photo_data["file"])
        return if bytes.nil?

        trip.cover_photo.attach(io: StringIO.new(bytes), filename: "cover#{File.extname(cover_photo_data["file"].to_s)}")
        unless allowed_image?(trip.cover_photo)
          trip.cover_photo.purge
          @warnings << "Skipped a non-image cover photo on '#{trip.title}'"
        end
      end

      def add_collaborators!(trip, usernames)
        Array(usernames).each do |username|
          user = User.find_by(username: username, adventurer: true)
          if user
            trip.trip_collaborators.find_or_create_by!(user: user)
          else
            @warnings << "Skipped unknown or non-adventurer collaborator '#{username}' on '#{trip.title}'"
          end
        end
      end

      def create_entry!(zip, trip, entry_data)
        entry = trip.trip_entries.new(
          title: entry_data["title"].presence || "Untitled entry",
          description: entry_data["description"],
          occurred_at: parse_time(entry_data["occurred_at"]),
          latitude: entry_data["latitude"],
          longitude: entry_data["longitude"],
          location_source: entry_data["location_source"] || (entry_data["manual_location"] ? "manual" : "automatic"),
          manual_time: !!entry_data["manual_time"],
          created_by: resolve_user(entry_data["created_by_username"])
        )
        entry.save!
        entry.update_column(:views_count, entry_data["views_count"].to_i) if entry_data["views_count"].present?

        Array(entry_data["photos"]).each { |photo_data| create_photo!(zip, entry, photo_data) }
        apply_location_photo!(entry, entry_data["location_photo_index"])
        create_comments!(entry, entry_data["comments"])
        create_reactions!(entry, entry_data["reactions"])
        tag_participants!(trip, entry, entry_data["tagged_collaborator_usernames"])

        entry
      end

      # Old-style manifests only recorded photo order via "position", not the
      # synthetic index this exporter now uses to point back at "the photo
      # whose location this entry uses" - so there's nothing to resolve for
      # those, and location_photo just stays unset (fine: "photo" without a
      # location_photo behaves the same as "automatic" finding no photos yet).
      def apply_location_photo!(entry, location_photo_index)
        return if location_photo_index.nil?

        photo = entry.photos.order(:position).to_a[location_photo_index]
        entry.update!(location_photo: photo) if photo
      end

      def create_photo!(zip, entry, photo_data)
        bytes = read_zip_entry(zip, photo_data["file"])
        return if bytes.nil?

        photo = entry.photos.create!(
          uploaded_by: resolve_user(photo_data["uploaded_by_username"]),
          position: photo_data["position"].to_i,
          latitude: photo_data["latitude"],
          longitude: photo_data["longitude"],
          taken_at: parse_time(photo_data["taken_at"]),
          image: { io: StringIO.new(bytes), filename: File.basename(photo_data["file"].to_s) }
        )

        unless allowed_image?(photo.image)
          photo.destroy!
          @warnings << "Skipped a non-image file in '#{entry.title}'"
        end
      end

      # Top-level comments are created first so replies can look their
      # parent up by the manifest's synthetic index; a reply whose
      # parent_index doesn't resolve to a top-level comment (unresolvable
      # author, or a manifest that (incorrectly) nests more than one level
      # deep) is imported as a top-level comment instead of being dropped.
      def create_comments!(entry, comments_data)
        comments = Array(comments_data).sort_by { |data| data["parent_index"].nil? ? 0 : 1 }
        comment_by_index = {}

        comments.each do |data|
          user = resolve_user(data["user_username"])
          next unless user

          parent = comment_by_index[data["parent_index"]]
          comment = entry.comments.create(body: data["body"], user: user, parent: parent)
          next unless comment.persisted?

          comment.update_column(:created_at, parse_time(data["created_at"])) if data["created_at"].present?
          comment_by_index[data["index"]] = comment
        end
      end

      def create_reactions!(entry, reactions_data)
        Array(reactions_data).each do |data|
          user = resolve_user(data["user_username"])
          next unless user

          reaction = entry.reactions.create(emoji: data["emoji"], user: user)
          if reaction.persisted?
            reaction.update_column(:created_at, parse_time(data["created_at"])) if data["created_at"].present?
          else
            @warnings << "Skipped a reaction on '#{entry.title}'"
          end
        end
      end

      def tag_participants!(trip, entry, usernames)
        Array(usernames).each do |username|
          user = resolve_user(username)
          next unless user && trip.editors.exists?(id: user.id)

          entry.tagged_collaborators << user unless entry.tagged_collaborators.include?(user)
        end
      end

      # --- shared helpers ---

      def resolve_user(username)
        return nil if username.blank?
        @user_cache.fetch(username) { @user_cache[username] = User.find_by(username: username) }
      end

      def read_zip_entry(zip, name)
        return nil if name.blank?
        zip.get_entry(name).get_input_stream.read
      rescue Errno::ENOENT
        nil
      end

      def allowed_image?(attachment)
        attachment.attached? && attachment.blob.content_type.in?(ALLOWED_IMAGE_CONTENT_TYPES)
      end

      def parse_time(value)
        return nil if value.blank?
        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
  end
end
