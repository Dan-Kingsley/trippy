# The single source of truth for which languages Trippy offers, and how to
# label/flag them - reused by the account settings selector, the signed-out
# header flag/modal, and the per-entry "written in" tag, so adding a language
# later (plus a new config/locales/<code>.yml) doesn't require touching each
# of those UIs separately.
module Locale
  OPTIONS = {
    "en" => [ "🇬🇧", "English" ],
    "de" => [ "🇩🇪", "Deutsch" ]
  }.freeze

  def self.select_options
    OPTIONS.map { |code, (flag, label)| [ "#{flag} #{label}", code ] }
  end
end
