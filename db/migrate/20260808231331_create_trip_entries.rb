class CreateTripEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :trip_entries do |t|
      t.references :trip, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.float :latitude
      t.float :longitude
      t.datetime :occurred_at
      t.boolean :manual_location, null: false, default: false
      t.boolean :manual_time, null: false, default: false
      t.references :created_by, null: true, foreign_key: { to_table: :users }

      t.timestamps
    end
    add_index :trip_entries, [ :trip_id, :occurred_at ]
  end
end
