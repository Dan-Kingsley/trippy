class TripEntry < ApplicationRecord
  LOCATION_SOURCES = %w[automatic photo manual].freeze

  belongs_to :trip
  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :location_photo, class_name: "Photo", optional: true

  has_many :photos, -> { order(:position) }, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :reactions, dependent: :destroy
  has_many :trip_entry_views, dependent: :destroy
  has_many :trip_entry_reads, dependent: :destroy
  has_many :trip_entry_collaborators, dependent: :destroy
  has_many :tagged_collaborators, through: :trip_entry_collaborators, source: :user

  before_validation :default_occurred_at

  validates :title, presence: true
  validates :occurred_at, presence: true
  validates :location_source, inclusion: { in: LOCATION_SOURCES }
  validates :language, inclusion: { in: I18n.available_locales.map(&:to_s) }

  # Keeps location/time in sync whenever the adventurer switches how either
  # one should be derived - Photo's own create/destroy callbacks (see
  # recompute_entry_later) handle the other trigger: the set of photos itself
  # changing. Guarded to the fields that actually change *this* record's
  # source, so the update! inside recompute_from_photos! (which only ever
  # touches latitude/longitude/occurred_at) can't re-trigger itself.
  after_update :recompute_from_photos!,
    if: -> { saved_change_to_location_source? || saved_change_to_location_photo_id? || saved_change_to_manual_time? }

  def located?
    latitude.present? && longitude.present?
  end

  # Recomputes location/time from attached photos' EXIF data, unless the
  # adventurer has manually overridden that dimension for this entry.
  def recompute_from_photos!
    located_photos = photos.select { |p| p.latitude.present? && p.longitude.present? }
    timed_photos = photos.select(&:taken_at)

    updates = {}
    case location_source
    when "automatic"
      if located_photos.any?
        updates[:latitude], updates[:longitude] = self.class.mean_coordinates(located_photos)
      end
    when "photo"
      if location_photo&.latitude.present?
        updates[:latitude] = location_photo.latitude
        updates[:longitude] = location_photo.longitude
      end
    end
    # "manual": leave latitude/longitude as whatever was submitted on the form.

    if !manual_time? && timed_photos.any?
      updates[:occurred_at] = self.class.mean_time(timed_photos)
    end

    update!(updates) if updates.any?
  end

  # Averages GPS coordinates on the surface of a sphere (via their Cartesian
  # unit vectors) rather than taking a naive arithmetic mean of latitude and
  # longitude independently. A plain mean of longitude breaks down for photos
  # that straddle the antimeridian (e.g. a trip through Fiji, ~+179/-179) -
  # it averages to ~0 deg (the opposite side of the globe) instead of ~180 deg.
  # This approach sidesteps that by construction, and also degrades gracefully
  # near the poles.
  def self.mean_coordinates(located_photos)
    sum_x, sum_y, sum_z = located_photos.reduce([ 0.0, 0.0, 0.0 ]) do |(sx, sy, sz), photo|
      lat, lng = photo.latitude * Math::PI / 180, photo.longitude * Math::PI / 180
      [ sx + Math.cos(lat) * Math.cos(lng), sy + Math.cos(lat) * Math.sin(lng), sz + Math.sin(lat) ]
    end

    count = located_photos.size
    x, y, z = sum_x / count, sum_y / count, sum_z / count

    lat = Math.atan2(z, Math.sqrt(x**2 + y**2))
    lng = Math.atan2(y, x)
    [ lat * 180 / Math::PI, lng * 180 / Math::PI ]
  end

  def self.mean_time(timed_photos)
    return nil if timed_photos.empty?

    average_seconds = timed_photos.sum { |p| p.taken_at.to_i } / timed_photos.size
    Time.zone.at(average_seconds)
  end

  SUGGESTION_SLOTS = 6

  def reaction_counts
    reactions.group(:emoji).count
  end

  # Emoji actually used on this entry come first, most-reacted first. Any
  # remaining slots (up to SUGGESTION_SLOTS total) are filled with unused
  # emoji suggestions - the user's own recently-used emoji take priority,
  # falling back to the default quick-pick set.
  def displayed_reaction_emojis(user: nil)
    used = reaction_counts.keys.sort_by { |emoji| -reaction_counts[emoji] }
    slots = [ SUGGESTION_SLOTS - used.size, 0 ].max
    return used if slots.zero?

    recent = user ? user.recent_emojis(limit: SUGGESTION_SLOTS) : []
    suggested = (recent + Reaction::QUICK_EMOJI).uniq - used
    used + suggested.first(slots)
  end

  # Everyone whose face should show on this entry: whoever created it, plus
  # anyone else tagged as having been there for that part of the trip.
  def participants
    ([ created_by ] + tagged_collaborators).compact.uniq
  end

  # Whether this entry should show an unread indicator to whoever `read`
  # (their TripEntryRead row for this entry, or nil) belongs to: :unread if
  # they've never opened it, :stale if they opened it but it's since been
  # edited and saved, or nil if they're fully caught up. Takes the read
  # record rather than a user so callers can preload it (see
  # TripsController#show) and avoid an N+1 across a whole page of entries.
  def unread_state(read)
    return :unread if read.nil?
    :stale if updated_at > read.updated_at
  end

  private
    # Guarantees every entry has a date & time, even without EXIF data or a
    # manual override - it falls back to when the entry was first uploaded.
    def default_occurred_at
      self.occurred_at ||= Time.current
    end
end
