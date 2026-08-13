class HomeController < ApplicationController
  def index
    private_trip_ids = Trip.where(public: false, secret_code: unlocked_trip_codes).pluck(:id)
    if Current.user
      private_trip_ids |= Current.user.trip_accesses.pluck(:trip_id)
      private_trip_ids |= Current.user.trips.pluck(:id)
    end

    accessible = Trip.where(public: true).or(Trip.where(id: private_trip_ids))

    # Anonymous visitors have nothing to favourite, so they always see "all".
    # Signed-in users default to "favourites" unless they've switched tabs.
    @tab = Current.user && params[:tab] != "all" ? "favourites" : "all"
    accessible = accessible.where(id: Current.user.favorite_trips.select(:id)) if @tab == "favourites"

    @trips = accessible.ordered_by_latest_entry
  end
end
