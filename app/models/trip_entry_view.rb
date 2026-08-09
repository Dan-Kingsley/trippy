class TripEntryView < ApplicationRecord
  belongs_to :trip_entry, counter_cache: :views_count
  belongs_to :user, optional: true

  validates :user_id, uniqueness: { scope: :trip_entry_id }, allow_nil: true
  validates :visitor_token, uniqueness: { scope: :trip_entry_id }, allow_nil: true
  validate :user_or_visitor_token_present

  private
    def user_or_visitor_token_present
      errors.add(:base, "must have a user or a visitor token") if user_id.blank? && visitor_token.blank?
    end
end
