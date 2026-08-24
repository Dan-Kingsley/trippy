class AddDescriptionToTrips < ActiveRecord::Migration[8.1]
  def change
    add_column :trips, :description, :text
  end
end
