class ProfilePictureVariantJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user&.profile_picture&.attached?

    user.profile_picture.variant(:thumb).processed
  rescue ActiveStorage::InvariableError => e
    Rails.logger.warn("ProfilePictureVariantJob: could not process user #{user_id} profile picture: #{e.message}")
  end
end
