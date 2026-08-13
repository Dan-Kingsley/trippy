class CreateFavorites < ActiveRecord::Migration[8.1]
  def change
    create_table :favorites do |t|
      t.references :trip, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :favorites, [ :trip_id, :user_id ], unique: true
    add_column :trips, :favorites_count, :integer, null: false, default: 0
  end
end
