class PhotosController < ApplicationController
  include PhotoUploadable

  before_action :require_authentication
  before_action :set_trip_and_entry
  before_action :require_editor

  def create
    rejected = attach_uploads(@entry)

    if rejected.any?
      redirect_to edit_trip_trip_entry_path(@trip, @entry),
        alert: t("photos.rejected", count: t("counts.file", count: rejected.size), reasons: rejected.uniq.join("; "))
    else
      redirect_to edit_trip_trip_entry_path(@trip, @entry), notice: t("photos.added")
    end
  end

  def update
    photo = @entry.photos.find(params[:id])
    photo.update!(position: params[:position])
    head :ok
  end

  def destroy
    @entry.photos.find(params[:id]).destroy
    redirect_to edit_trip_trip_entry_path(@trip, @entry), notice: t("photos.removed")
  end

  private
    def set_trip_and_entry
      @trip = Trip.find_by!(slug: params[:trip_slug])
      @entry = @trip.trip_entries.find(params[:trip_entry_id])
    end

    def require_editor
      unless Current.user.can_edit?(@trip)
        redirect_to trip_path(@trip), alert: t("photos.not_editor")
      end
    end
end
