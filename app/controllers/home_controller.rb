class HomeController < ApplicationController
  def index
    private_trip_ids = Trip.where(public: false, secret_code: unlocked_trip_codes).pluck(:id)
    private_trip_ids |= Current.user.trip_accesses.pluck(:trip_id) if Current.user

    @trips = Trip.where(public: true).or(Trip.where(id: private_trip_ids)).ordered_by_latest_entry
  end
end
