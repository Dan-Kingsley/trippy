class SettingsController < ApplicationController
  before_action :require_authentication

  def edit
    @user = Current.user
  end

  def update
    @user = Current.user
    if @user.update(user_params)
      redirect_to edit_settings_path, notice: "Settings updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def user_params
      params.require(:user).permit(:username, :password, :password_confirmation, :profile_picture)
    end
end
