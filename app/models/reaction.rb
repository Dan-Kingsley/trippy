class Reaction < ApplicationRecord
  QUICK_EMOJI = %w[👍 ❤️ 😂 😮 🎉 😢].freeze

  belongs_to :trip_entry, counter_cache: true
  belongs_to :user

  validates :emoji, presence: true
  validates :user_id, uniqueness: { scope: [ :trip_entry_id, :emoji ] }
  validate :emoji_is_a_single_emoji

  private
    # Accepts any single emoji grapheme (including multi-codepoint ones like
    # skin tones, flags and ZWJ family sequences), rejecting plain text.
    def emoji_is_a_single_emoji
      return if emoji.blank?

      unless emoji.grapheme_clusters.one? && emoji.match?(/\p{Emoji}/)
        errors.add(:emoji, :invalid)
      end
    end
end
