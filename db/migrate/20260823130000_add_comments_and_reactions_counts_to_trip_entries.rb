class AddCommentsAndReactionsCountsToTripEntries < ActiveRecord::Migration[8.1]
  def up
    add_column :trip_entries, :comments_count, :integer, null: false, default: 0
    add_column :trip_entries, :reactions_count, :integer, null: false, default: 0

    execute <<~SQL
      UPDATE trip_entries SET comments_count = (
        SELECT COUNT(*) FROM comments WHERE comments.trip_entry_id = trip_entries.id
      )
    SQL
    execute <<~SQL
      UPDATE trip_entries SET reactions_count = (
        SELECT COUNT(*) FROM reactions WHERE reactions.trip_entry_id = trip_entries.id
      )
    SQL
  end

  def down
    remove_column :trip_entries, :comments_count
    remove_column :trip_entries, :reactions_count
  end
end
