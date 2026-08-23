class AddLocationSourceToTripEntries < ActiveRecord::Migration[8.1]
  class MigrationTripEntry < ActiveRecord::Base
    self.table_name = "trip_entries"
  end

  def up
    add_column :trip_entries, :location_source, :string, default: "automatic", null: false
    add_reference :trip_entries, :location_photo, foreign_key: { to_table: :photos, on_delete: :nullify }, null: true

    MigrationTripEntry.reset_column_information
    MigrationTripEntry.where(manual_location: true).update_all(location_source: "manual")

    remove_column :trip_entries, :manual_location
  end

  def down
    add_column :trip_entries, :manual_location, :boolean, default: false, null: false

    MigrationTripEntry.reset_column_information
    MigrationTripEntry.where(location_source: "manual").update_all(manual_location: true)

    remove_reference :trip_entries, :location_photo
    remove_column :trip_entries, :location_source
  end
end
