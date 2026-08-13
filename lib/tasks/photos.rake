namespace :photos do
  desc "Pre-generate :thumb and :full variants for photos that don't have them yet"
  task backfill_variants: :environment do
    Photo.joins(:image_attachment).find_each do |photo|
      PhotoVariantJob.perform_later(photo.id)
    end
  end
end
