class TripCollaboratorsController < ApplicationController
  before_action :require_authentication
  before_action :set_trip
  before_action :require_owner_or_admin

  def create
    user = User.find_by(username: params[:username].to_s.strip.downcase, adventurer: true)
    if user.nil?
      redirect_to edit_trip_path(@trip), alert: "No adventurer found with that username." and return
    end

    @trip.trip_collaborators.find_or_create_by!(user: user)
    redirect_to edit_trip_path(@trip), notice: "#{user.username} can now edit this trip."
  end

  def destroy
    @trip.trip_collaborators.where(user_id: params[:id]).destroy_all
    redirect_to edit_trip_path(@trip), notice: "Collaborator removed."
  end

  private
    def set_trip
      @trip = Trip.find_by!(slug: params[:trip_slug])
    end

    def require_owner_or_admin
      unless Current.user.admin? || @trip.owner_id == Current.user.id
        redirect_to trip_path(@trip), alert: "Only the trip owner can manage collaborators."
      end
    end
end
