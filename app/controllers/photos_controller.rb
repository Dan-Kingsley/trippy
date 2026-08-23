class PhotosController < ApplicationController
  include PhotoUploadable

  before_action :require_authentication
  before_action :set_trip_and_entry
  before_action :require_editor

  def create
    rejected = attach_uploads(@entry)

    if rejected.positive?
      redirect_to edit_trip_trip_entry_path(@trip, @entry),
        alert: "#{rejected} #{'file'.pluralize(rejected)} couldn't be added - only photo and video files are supported."
    else
      redirect_to edit_trip_trip_entry_path(@trip, @entry), notice: "Photos added."
    end
  end

  def update
    photo = @entry.photos.find(params[:id])
    photo.update!(position: params[:position])
    head :ok
  end

  def destroy
    @entry.photos.find(params[:id]).destroy
    redirect_to edit_trip_trip_entry_path(@trip, @entry), notice: "Photo removed."
  end

  private
    def set_trip_and_entry
      @trip = Trip.find_by!(slug: params[:trip_slug])
      @entry = @trip.trip_entries.find(params[:trip_entry_id])
    end

    def require_editor
      unless Current.user.can_edit?(@trip)
        redirect_to trip_path(@trip), alert: "You don't have edit access to this trip."
      end
    end
end
