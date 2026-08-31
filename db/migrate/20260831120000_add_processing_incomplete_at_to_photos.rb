class AddProcessingIncompleteAtToPhotos < ActiveRecord::Migration[8.1]
  def change
    add_column :photos, :processing_incomplete_at, :datetime
  end
end
