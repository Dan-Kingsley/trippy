class Trip < ApplicationRecord
  SECRET_CODE_LENGTH = 32
  COVER_SOURCES = %w[ auto upload photo ]

  belongs_to :owner, class_name: "User"
  belongs_to :cover_photo_record, class_name: "Photo", foreign_key: :cover_photo_id, optional: true

  has_many :trip_collaborators, dependent: :destroy
  has_many :collaborators, through: :trip_collaborators, source: :user
  has_many :trip_accesses, dependent: :destroy
  has_many :trip_entries, -> { order(:occurred_at) }, dependent: :destroy
  has_many :favorites, dependent: :destroy
  has_many :favorited_by, through: :favorites, source: :user
  has_one_attached :cover_photo do |attachable|
    # See Photo#image for why fail_on: :none, unlimited: true - a real
    # high-megapixel phone photo (e.g. Pixel 9 Pro) can trip libjpeg's
    # decompression-bomb guard as a false positive.
    attachable.variant :thumb, resize_to_fill: [ 600, 400 ], saver: { quality: 80 }, loader: { fail_on: :none, unlimited: true }
  end

  validates :title, presence: true
  validates :description, length: { maximum: 300 }
  validates :cover_source, inclusion: { in: COVER_SOURCES }
  validate :acceptable_cover_photo_content_type

  before_validation :assign_slug
  before_validation :assign_secret_code, on: :create

  # Trips with no dated entries yet sort to the end, newest-entry trips first.
  scope :ordered_by_latest_entry, -> {
    left_joins(:trip_entries)
      .group("trips.id")
      .order(Arel.sql("MAX(trip_entries.occurred_at) IS NULL, MAX(trip_entries.occurred_at) DESC"))
  }

  def to_param
    slug
  end

  def editors
    User.where(id: [ owner_id, *collaborator_ids ])
  end

  def favorited_by?(user)
    user && favorites.exists?(user_id: user.id)
  end

  # Every photo across this trip's entries, most recently uploaded first -
  # used to let an adventurer pick one as the trip's cover image.
  def photos
    Photo.where(trip_entry_id: trip_entries.select(:id)).order(created_at: :desc)
  end

  # Three ways to pick a trip's cover image: an explicitly uploaded photo, an
  # existing photo picked from one of the trip's own entries, or (the
  # default) automatically the most recent entry's first photo. Each mode
  # falls back to "auto" if its chosen source turns out to be unusable
  # (upload removed, picked photo deleted), rather than showing nothing.
  def cover_image
    case cover_source
    when "upload"
      cover_photo.attached? ? cover_photo : auto_cover_image
    when "photo"
      cover_photo_record&.image&.attached? ? cover_photo_record.image : auto_cover_image
    else
      auto_cover_image
    end
  end

  # The span the trip actually covers, based on when its entries happened
  # rather than when they were logged - nil if there are no dated entries yet.
  def entry_date_range
    first = trip_entries.minimum(:occurred_at)
    return nil unless first

    [ first, trip_entries.maximum(:occurred_at) ]
  end

  private
    # Regenerates the slug (and so the trip's URL) whenever the title changes,
    # not just on creation, so the URL always reflects the current name.
    def assign_slug
      return if slug.present? && !title_changed?

      base = title.to_s.parameterize
      base = "trip" if base.blank?
      loop do
        candidate = "#{base}-#{SecureRandom.alphanumeric(6).downcase}"
        scope = Trip.where(slug: candidate)
        scope = scope.where.not(id: id) if persisted?
        unless scope.exists?
          self.slug = candidate
          break
        end
      end
    end

    def assign_secret_code
      return if secret_code.present?

      loop do
        candidate = SecureRandom.alphanumeric(SECRET_CODE_LENGTH)
        unless Trip.exists?(secret_code: candidate)
          self.secret_code = candidate
          break
        end
      end
    end

    def acceptable_cover_photo_content_type
      return unless cover_photo.attached?
      return if cover_photo.content_type.in?(MediaContentTypes::IMAGES)

      errors.add(:cover_photo, :invalid_content_type)
    end

    # trip_entries is ordered ascending by occurred_at, so the latest entry
    # is the last one, not the first.
    def auto_cover_image
      trip_entries.last&.photos&.first&.image
    end
end
