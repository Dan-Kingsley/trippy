class TripEntry < ApplicationRecord
  belongs_to :trip
  belongs_to :created_by, class_name: "User", optional: true

  has_many :photos, -> { order(:position) }, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :reactions, dependent: :destroy

  validates :title, presence: true

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

  def reaction_counts
    reactions.group(:emoji).count
  end
end
