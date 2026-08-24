class ExportsController < ApplicationController
  before_action :require_authentication

  def show
    if params[:trip_slug].present?
      export_single_trip
    else
      export_owned_trips
    end
  end

  private
    def export_single_trip
      trip = Trip.find_by!(slug: params[:trip_slug])
      unless Current.user.can_edit?(trip)
        redirect_to trip_path(trip), alert: t("exports.not_editor") and return
      end

      stream_zip([ trip ], "trippy-#{trip.slug}-#{Date.current.iso8601}.zip")
    end

    def export_owned_trips
      stream_zip(Current.user.owned_trips.to_a, "trippy-all-trips-#{Date.current.iso8601}.zip")
    end

    def stream_zip(trips, filename)
      tempfile = Exporting::TripArchiveBuilder.new(trips).build
      send_data tempfile.read, filename: filename, type: "application/zip", disposition: "attachment"
    ensure
      tempfile&.close
      tempfile&.unlink
    end
end
