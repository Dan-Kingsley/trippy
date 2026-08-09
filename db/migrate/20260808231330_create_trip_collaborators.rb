class CreateTripCollaborators < ActiveRecord::Migration[8.1]
  def change
    create_table :trip_collaborators do |t|
      t.references :trip, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    add_index :trip_collaborators, [ :trip_id, :user_id ], unique: true
  end
end
