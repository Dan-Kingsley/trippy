class TripEntry < ApplicationRecord
  belongs_to :trip
  belongs_to :created_by, class_name: "User", optional: true

  has_many :photos, -> { order(:position) }, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :reactions, dependent: :destroy
  has_many :trip_entry_views, dependent: :destroy
  has_many :trip_entry_collaborators, dependent: :destroy
  has_many :tagged_collaborators, through: :trip_entry_collaborators, source: :user

  before_validation :default_occurred_at

  validates :title, presence: true
  validates :occurred_at, presence: true

  def located?
    latitude.present? && longitude.present?
  end

  # Recomputes location/time from attached photos' EXIF data, unless the
  # adventurer has manually overridden that dimension for this entry.
  def recompute_from_photos!
    located_photos = photos.select { |p| p.latitude.present? && p.longitude.present? }
    timed_photos = photos.select(&:taken_at)

    updates = {}
    if !manual_location? && located_photos.any?
      updates[:latitude] = located_photos.sum(&:latitude) / located_photos.size
      updates[:longitude] = located_photos.sum(&:longitude) / located_photos.size
    end
    if !manual_time? && timed_photos.any?
      average_seconds = timed_photos.sum { |p| p.taken_at.to_i } / timed_photos.size
      updates[:occurred_at] = Time.zone.at(average_seconds)
    end

    update!(updates) if updates.any?
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

  private
    # Guarantees every entry has a date & time, even without EXIF data or a
    # manual override - it falls back to when the entry was first uploaded.
    def default_occurred_at
      self.occurred_at ||= Time.current
    end
end
