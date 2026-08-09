class CreatePhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :photos do |t|
      t.references :trip_entry, null: false, foreign_key: true
      t.references :uploaded_by, null: true, foreign_key: { to_table: :users }
      t.integer :position, null: false, default: 0
      t.float :latitude
      t.float :longitude
      t.datetime :taken_at

      t.timestamps
    end
    add_index :photos, [ :trip_entry_id, :position ]
  end
end
