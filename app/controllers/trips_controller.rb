class TripsController < ApplicationController
  before_action :require_adventurer, only: %i[ index new create ]
  before_action :set_trip, only: %i[ show edit update destroy ]
  before_action :require_editor, only: %i[ edit update ]
  before_action :require_owner_or_admin, only: %i[ destroy ]

  def index
    @trips = Current.user.trips.ordered_by_latest_entry
  end

  def show
    if params[:code].present? && params[:code] == @trip.secret_code && !unlocked_trip_codes.include?(@trip.secret_code)
      remember_trip_code!(@trip.secret_code)
    end

    unless trip_accessible?(@trip)
      redirect_to root_path, alert: "This trip is private. Enter its access code to view it." and return
    end

    @entries = @trip.trip_entries.includes(
      photos: { image_attachment: :blob },
      created_by: { profile_picture_attachment: :blob },
      tagged_collaborators: { profile_picture_attachment: :blob }
    )
    @editable = Current.user&.can_edit?(@trip) || false
    @can_add_entries = Current.user&.can_add_entries?(@trip) || false
    @trip_member = Current.user && @trip.editors.exists?(id: Current.user.id)
  end

  def new
    @trip = Trip.new
  end

  def create
    @trip = Trip.new(trip_params)
    @trip.owner = Current.user

    if @trip.save
      redirect_to trip_path(@trip), notice: "Trip created. Start adding entries!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @trip.update(trip_params)
      redirect_to trip_path(@trip), notice: "Trip updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @trip.destroy
    redirect_to trips_path, notice: "Trip deleted.", status: :see_other
  end

  private
    def set_trip
      @trip = Trip.find_by!(slug: params[:slug])
    end

    def require_editor
      require_authentication
      unless performed? || Current.user.can_edit?(@trip)
        redirect_to trip_path(@trip), alert: "You don't have edit access to this trip."
      end
    end

    def require_owner_or_admin
      require_authentication
      unless performed? || Current.user.admin? || @trip.owner_id == Current.user.id
        redirect_to trip_path(@trip), alert: "Only the trip owner can do that."
      end
    end

    def trip_params
      params.require(:trip).permit(:title, :public, :cover_photo)
    end
end
