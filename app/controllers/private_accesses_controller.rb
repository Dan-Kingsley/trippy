class PrivateAccessesController < ApplicationController
  rate_limit to: 20, within: 3.minutes, only: :create, with: -> { redirect_to root_path, alert: "Try again later." }

  def create
    code = params[:code].to_s.strip
    trip = Trip.find_by(public: false, secret_code: code)

    if trip
      remember_trip_code!(trip.secret_code)
      TripAccess.find_or_create_by(trip: trip, user: Current.user) if Current.user
      redirect_to trip_path(trip)
    else
      redirect_to root_path, alert: "That code doesn't match any private trip."
    end
  end
end
