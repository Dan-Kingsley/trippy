class CreateTrips < ActiveRecord::Migration[8.1]
  def change
    create_table :trips do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.boolean :public, null: false, default: false
      t.string :secret_code, null: false
      t.references :owner, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
    add_index :trips, :slug, unique: true
    add_index :trips, :secret_code, unique: true
  end
end
