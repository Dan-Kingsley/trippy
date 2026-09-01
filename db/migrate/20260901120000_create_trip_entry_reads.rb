class CreateTripEntryReads < ActiveRecord::Migration[8.1]
  def change
    create_table :trip_entry_reads do |t|
      t.references :trip_entry, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :trip_entry_reads, [ :trip_entry_id, :user_id ], unique: true
  end
end
