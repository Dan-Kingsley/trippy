class Reaction < ApplicationRecord
  EMOJI_OPTIONS = %w[👍 ❤️ 😂 😮 🎉 😢].freeze

  belongs_to :trip_entry
  belongs_to :user

  validates :emoji, inclusion: { in: EMOJI_OPTIONS }
  validates :user_id, uniqueness: { scope: [ :trip_entry_id, :emoji ] }
end
