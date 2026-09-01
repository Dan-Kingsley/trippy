class TripEntryRead < ApplicationRecord
  belongs_to :trip_entry
  belongs_to :user

  validates :user_id, uniqueness: { scope: :trip_entry_id }
end
