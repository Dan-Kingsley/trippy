class AddHiddenToTripsAndTripEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :trips, :hidden, :boolean, default: false, null: false
    add_column :trip_entries, :hidden, :boolean, default: false, null: false
  end
end
