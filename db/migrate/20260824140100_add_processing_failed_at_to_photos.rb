class AddProcessingFailedAtToPhotos < ActiveRecord::Migration[8.1]
  def change
    add_column :photos, :processing_failed_at, :datetime
  end
end
