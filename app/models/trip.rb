class Trip < ApplicationRecord
  SECRET_CODE_LENGTH = 32

  belongs_to :owner, class_name: "User"

  has_many :trip_collaborators, dependent: :destroy
  has_many :collaborators, through: :trip_collaborators, source: :user
  has_many :trip_accesses, dependent: :destroy
  has_many :trip_entries, -> { order(:occurred_at) }, dependent: :destroy
  has_one_attached :cover_photo

  validates :title, presence: true

  before_validation :assign_slug, on: :create
  before_validation :assign_secret_code, on: :create

  def to_param
    slug
  end

  def editors
    User.where(id: [ owner_id, *collaborator_ids ])
  end

  def cover_image
    return cover_photo if cover_photo.attached?
    trip_entries.first&.photos&.first&.image
  end

  private
    def assign_slug
      return if slug.present?

      base = title.to_s.parameterize
      base = "trip" if base.blank?
      loop do
        candidate = "#{base}-#{SecureRandom.alphanumeric(6).downcase}"
        unless Trip.exists?(slug: candidate)
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
