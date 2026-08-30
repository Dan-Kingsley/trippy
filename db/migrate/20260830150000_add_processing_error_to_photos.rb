class AddProcessingErrorToPhotos < ActiveRecord::Migration[8.1]
  def change
    add_column :photos, :processing_error, :text
  end
end
