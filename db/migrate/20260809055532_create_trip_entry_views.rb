class CreateTripEntryViews < ActiveRecord::Migration[8.1]
  def change
    create_table :trip_entry_views do |t|
      t.references :trip_entry, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :visitor_token

      t.timestamps
    end

    add_index :trip_entry_views, [ :trip_entry_id, :user_id ], unique: true
    add_index :trip_entry_views, [ :trip_entry_id, :visitor_token ], unique: true

    add_column :trip_entries, :views_count, :integer, null: false, default: 0
  end
end
