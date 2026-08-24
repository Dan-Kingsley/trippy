class AddLanguageToTripEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :trip_entries, :language, :string, default: "en", null: false
  end
end
