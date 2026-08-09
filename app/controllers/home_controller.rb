class HomeController < ApplicationController
  def index
    private_trip_ids = Trip.where(public: false, secret_code: unlocked_trip_codes).pluck(:id)
    if Current.user
      private_trip_ids |= Current.user.trip_accesses.pluck(:trip_id)
      private_trip_ids |= Current.user.trips.pluck(:id)
    end

    @trips = Trip.where(public: true).or(Trip.where(id: private_trip_ids)).ordered_by_latest_entry
  end
end
