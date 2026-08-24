class Comment < ApplicationRecord
  belongs_to :trip_entry, counter_cache: true
  belongs_to :user
  belongs_to :parent, class_name: "Comment", optional: true, inverse_of: :replies
  has_many :replies, -> { order(:created_at) }, class_name: "Comment", foreign_key: :parent_id,
    dependent: :destroy, inverse_of: :parent

  validates :body, presence: true, length: { maximum: 2000 }
  validate :parent_is_a_top_level_comment_in_the_same_entry

  private
    def parent_is_a_top_level_comment_in_the_same_entry
      return if parent.nil?
      errors.add(:parent, :wrong_entry) if parent.trip_entry_id != trip_entry_id
      errors.add(:parent, :nested_reply) if parent.parent_id.present?
    end
end
