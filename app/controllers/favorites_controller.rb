class FavoritesController < ApplicationController
  before_action :require_authentication
  before_action :set_trip

  def create
    unless trip_accessible?(@trip)
      redirect_to root_path, alert: "This trip is private." and return
    end

    @trip.favorites.find_or_create_by(user: Current.user)
    redirect_back fallback_location: trip_path(@trip)
  end

  def destroy
    @trip.favorites.where(user: Current.user).destroy_all
    redirect_back fallback_location: trip_path(@trip)
  end

  private
    def set_trip
      @trip = Trip.find_by!(slug: params[:trip_slug])
    end
end
