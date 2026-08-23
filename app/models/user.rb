class User < ApplicationRecord
  has_secure_password
  has_one_attached :profile_picture do |attachable|
    # A single prewarmed size, reused (and scaled down by the browser) at
    # every display size the app renders avatars at - keeps the number of
    # variants that can fail to process down to one per user, rather than
    # one per distinct `size:` an avatar_tag call site happens to pass.
    attachable.variant :thumb, resize_to_fill: [ 128, 128 ], saver: { quality: 80 }
  end
  has_many :sessions, dependent: :destroy

  has_many :owned_trips, class_name: "Trip", foreign_key: :owner_id, dependent: :destroy
  has_many :trip_collaborators, dependent: :destroy
  has_many :collaborating_trips, through: :trip_collaborators, source: :trip
  has_many :trip_accesses, dependent: :destroy
  has_many :trip_entries, foreign_key: :created_by_id, dependent: :nullify, inverse_of: :created_by
  has_many :photos, foreign_key: :uploaded_by_id, dependent: :nullify, inverse_of: :uploaded_by
  has_many :comments, dependent: :destroy
  has_many :reactions, dependent: :destroy
  has_many :favorites, dependent: :destroy
  has_many :favorite_trips, through: :favorites, source: :trip

  normalizes :username, with: ->(value) { value.strip.downcase }

  validates :username, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9_.-]+\z/, message: "can only contain letters, numbers, dots, dashes and underscores" }
  validates :password, length: { minimum: 8 }, allow_nil: true
  validate :acceptable_profile_picture_content_type

  before_create :bootstrap_first_user_as_admin

  def trips
    Trip.where(id: owned_trips.select(:id)).or(Trip.where(id: collaborating_trips.select(:id)))
  end

  def can_edit?(trip)
    admin? || trip.owner_id == id || trip.collaborators.exists?(id: id)
  end

  # Unlike can_edit?, excludes admins: only the trip's own owner/collaborators
  # may add new entries, since admins moderate rather than author content.
  def can_add_entries?(trip)
    trip.owner_id == id || trip.collaborators.exists?(id: id)
  end

  # This user's own emoji, most-recently-used first, across all trips -
  # used to personalize reaction suggestions and the emoji picker.
  def recent_emojis(limit: 6)
    reactions.order(created_at: :desc).limit(50).pluck(:emoji).uniq.first(limit)
  end

  private
    def bootstrap_first_user_as_admin
      if User.count.zero?
        self.admin = true
        self.adventurer = true
      end
    end

    def acceptable_profile_picture_content_type
      return unless profile_picture.attached?
      return if profile_picture.content_type.in?(MediaContentTypes::IMAGES)

      errors.add(:profile_picture, "must be a supported photo format")
    end
end
