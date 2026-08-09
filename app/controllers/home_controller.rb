class HomeController < ApplicationController
  def index
    @public_trips = Trip.where(public: true).ordered_by_latest_entry

    codes = unlocked_trip_codes
    @private_trips = codes.any? ? Trip.where(public: false, secret_code: codes).ordered_by_latest_entry : Trip.none
  end
end
