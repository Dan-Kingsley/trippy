class CreateReactions < ActiveRecord::Migration[8.1]
  def change
    create_table :reactions do |t|
      t.references :trip_entry, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :emoji, null: false

      t.timestamps
    end
    add_index :reactions, [ :trip_entry_id, :user_id, :emoji ], unique: true, name: "index_reactions_on_entry_user_emoji"
  end
end
