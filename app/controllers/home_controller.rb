class HomeController < ApplicationController
  def index
    @public_trips = Trip.where(public: true).order(created_at: :desc)

    codes = unlocked_trip_codes
    @private_trips = codes.any? ? Trip.where(public: false, secret_code: codes).order(created_at: :desc) : Trip.none
  end
end
