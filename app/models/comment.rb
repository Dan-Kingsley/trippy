class Comment < ApplicationRecord
  belongs_to :trip_entry
  belongs_to :user

  validates :body, presence: true, length: { maximum: 2000 }
end
