class AddCoverSourceToTrips < ActiveRecord::Migration[8.1]
  def change
    add_column :trips, :cover_source, :string, default: "auto", null: false
    add_reference :trips, :cover_photo, foreign_key: { to_table: :photos, on_delete: :nullify }, null: true
  end
end
