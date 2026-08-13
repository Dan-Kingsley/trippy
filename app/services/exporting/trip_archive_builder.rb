module Exporting
  # Serializes one or more trips (with their entries, photos, comments,
  # reactions, collaborators, and tagged participants) into a self-contained
  # .zip: a manifest.json describing the data plus the original photo bytes.
  #
  # See Importing::TripArchiveImporter for the reverse operation and the
  # authoritative description of the manifest schema both sides agree on.
  class TripArchiveBuilder
    FORMAT_VERSION = 1

    def initialize(trips)
      @trips = Array(trips)
    end

    # Returns a rewound Tempfile containing the zip. The caller is
    # responsible for closing/unlinking it once the response is sent.
    def build
      tempfile = Tempfile.new([ "trippy-export", ".zip" ], binmode: true)

      manifest = {
        "trippy_export_version" => FORMAT_VERSION,
        "exported_at" => Time.current.iso8601,
        "trips" => []
      }

      Zip::File.open(tempfile.path, create: true) do |zip|
        @trips.each_with_index do |trip, trip_index|
          manifest["trips"] << export_trip(zip, trip, trip_index)
        end
        zip.get_output_stream("manifest.json") { |out| out.write(JSON.pretty_generate(manifest)) }
      end

      # Zip::File#commit replaces the file at this path via a rename, which
      # orphans our original Tempfile's file handle (still pointing at the
      # old, empty inode). Reopen it so reads see the actual zip contents.
      tempfile.close
      tempfile.open
      tempfile
    end

    private
      def export_trip(zip, trip, trip_index)
        base = "trips/#{trip_index}"

        data = {
          "secret_code" => trip.secret_code,
          "title" => trip.title,
          "public" => trip.public,
          "collaborators" => trip.collaborators.pluck(:username),
          "entries" => trip.trip_entries.order(:occurred_at).each_with_index.map { |entry, i| export_entry(zip, entry, base, i) }
        }

        if trip.cover_photo.attached?
          file = "#{base}/cover_photo#{extension_for(trip.cover_photo)}"
          write_blob(zip, file, trip.cover_photo)
          data["cover_photo"] = { "file" => file }
        end

        data
      end

      def export_entry(zip, entry, trip_base, entry_index)
        base = "#{trip_base}/entries/#{entry_index}"

        {
          "title" => entry.title,
          "description" => entry.description,
          "occurred_at" => entry.occurred_at&.iso8601,
          "latitude" => entry.latitude,
          "longitude" => entry.longitude,
          "manual_location" => entry.manual_location,
          "manual_time" => entry.manual_time,
          "views_count" => entry.views_count,
          "created_by_username" => entry.created_by&.username,
          "tagged_collaborator_usernames" => entry.tagged_collaborators.pluck(:username),
          "photos" => entry.photos.order(:position).each_with_index.map { |photo, i| export_photo(zip, photo, base, i) },
          "comments" => export_comments(entry),
          "reactions" => entry.reactions.map { |reaction|
            {
              "emoji" => reaction.emoji,
              "user_username" => reaction.user.username,
              "created_at" => reaction.created_at.iso8601
            }
          }
        }
      end

      def export_photo(zip, photo, entry_base, photo_index)
        file = "#{entry_base}/photos/#{photo_index}#{extension_for(photo.image)}"
        write_blob(zip, file, photo.image)

        {
          "file" => file,
          "position" => photo.position,
          "latitude" => photo.latitude,
          "longitude" => photo.longitude,
          "taken_at" => photo.taken_at&.iso8601,
          "uploaded_by_username" => photo.uploaded_by&.username
        }
      end

      # Flattens an entry's (at most one-level-deep) comment thread into an
      # array with synthetic index/parent_index references, since real
      # database ids mean nothing on the importing side.
      def export_comments(entry)
        top_level = entry.comments.where(parent_id: nil).order(:created_at).includes(:replies)

        flattened = []
        top_level.each do |comment|
          flattened << comment
          comment.replies.order(:created_at).each { |reply| flattened << reply }
        end

        index_by_id = flattened.each_with_index.to_h { |comment, i| [ comment.id, i ] }

        flattened.each_with_index.map do |comment, i|
          {
            "index" => i,
            "parent_index" => comment.parent_id ? index_by_id[comment.parent_id] : nil,
            "body" => comment.body,
            "user_username" => comment.user.username,
            "created_at" => comment.created_at.iso8601
          }
        end
      end

      def write_blob(zip, path, attachment)
        zip.get_output_stream(path) do |out|
          attachment.blob.open { |file| IO.copy_stream(file, out) }
        end
      end

      def extension_for(attachment)
        ext = ::File.extname(attachment.blob.filename.to_s)
        ext.presence || ".bin"
      end
  end
end
