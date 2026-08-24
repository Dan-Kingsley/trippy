class PrivateAccessesController < ApplicationController
  rate_limit to: 20, within: 3.minutes, only: :create, with: -> { redirect_to root_path, alert: t("private_accesses.try_again_later") }

  def create
    code = params[:code].to_s.strip
    trip = Trip.find_by(public: false, secret_code: code)

    if trip
      remember_trip_code!(trip.secret_code)
      grant_trip_access!(trip)
      redirect_to trip_path(trip)
    else
      redirect_to root_path, alert: t("private_accesses.invalid_code")
    end
  end
end
