class Admin::UsersController < ApplicationController
  before_action :require_admin

  def index
    @users = User.order(:username)
  end

  def update
    user = User.find(params[:id])
    user.update!(user_params)
    redirect_to admin_users_path, notice: t("admin.users.updated", username: user.username)
  end

  def grant_adventurer
    user = User.find_by(username: params[:username].to_s.strip.downcase)
    if user
      user.update!(adventurer: true)
      redirect_to admin_users_path, notice: t("admin.users.granted_adventurer", username: user.username)
    else
      redirect_to admin_users_path, alert: t("admin.users.user_not_found")
    end
  end

  private
    def user_params
      params.permit(:adventurer, :admin)
    end

    def require_admin
      redirect_to root_path, alert: t("admin.users.not_authorized") unless Current.user&.admin?
    end
end
