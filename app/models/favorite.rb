class Favorite < ApplicationRecord
  belongs_to :trip, counter_cache: :favorites_count
  belongs_to :user

  validates :user_id, uniqueness: { scope: :trip_id }
end
