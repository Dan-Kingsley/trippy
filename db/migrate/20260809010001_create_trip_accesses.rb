class CreateTripAccesses < ActiveRecord::Migration[8.1]
  def change
    create_table :trip_accesses do |t|
      t.references :trip, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    add_index :trip_accesses, [ :trip_id, :user_id ], unique: true
  end
end
