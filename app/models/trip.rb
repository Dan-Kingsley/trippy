class Trip < ApplicationRecord
  SECRET_CODE_LENGTH = 32

  belongs_to :owner, class_name: "User"

  has_many :trip_collaborators, dependent: :destroy
  has_many :collaborators, through: :trip_collaborators, source: :user
  has_many :trip_accesses, dependent: :destroy
  has_many :trip_entries, -> { order(:occurred_at) }, dependent: :destroy
  has_many :favorites, dependent: :destroy
  has_many :favorited_by, through: :favorites, source: :user
  has_one_attached :cover_photo

  validates :title, presence: true

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

  def cover_image
    return cover_photo if cover_photo.attached?
    trip_entries.first&.photos&.first&.image
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
end
