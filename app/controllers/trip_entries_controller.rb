class TripEntriesController < ApplicationController
  before_action :set_trip
  before_action :require_view_access, only: %i[ show ]
  before_action :require_authentication, except: %i[ show ]
  before_action :require_editor, except: %i[ show ]
  before_action :set_entry, only: %i[ show edit update destroy ]

  def show
    @comments = @entry.comments.where(parent_id: nil).includes(:user, replies: :user).order(:created_at)
    @editable = Current.user&.can_edit?(@trip) || false
    record_view!
  end

  def new
    @entry = @trip.trip_entries.new
  end

  def create
    @entry = @trip.trip_entries.new(entry_params)
    @entry.created_by = Current.user

    if @entry.save
      attach_photos(@entry)
      redirect_to trip_path(@trip), notice: "Entry added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @entry.update(entry_params)
      attach_photos(@entry)
      redirect_to trip_path(@trip), notice: "Entry updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @entry.destroy
    redirect_to trip_path(@trip), notice: "Entry deleted.", status: :see_other
  end

  private
    def set_trip
      @trip = Trip.find_by!(slug: params[:trip_slug])
    end

    def set_entry
      @entry = @trip.trip_entries.find(params[:id])
    end

    def require_view_access
      unless trip_accessible?(@trip)
        redirect_to root_path, alert: "This trip is private. Enter its access code to view it."
      end
    end

    def require_editor
      unless performed? || Current.user.can_edit?(@trip)
        redirect_to trip_path(@trip), alert: "You don't have edit access to this trip."
      end
    end

    # Skips the trip's owner/collaborators so they don't inflate view counts
    # on their own trips, and dedupes repeat visits by account (signed in)
    # or by a persistent per-device cookie (anonymous).
    def record_view!
      return if Current.user && @trip.editors.exists?(id: Current.user.id)

      attrs = Current.user ? { user: Current.user } : { visitor_token: visitor_token }
      @entry.trip_entry_views.find_or_create_by(attrs)
    end

    def visitor_token
      cookies.signed[:visitor_token] || begin
        token = SecureRandom.uuid
        cookies.signed.permanent[:visitor_token] = { value: token, httponly: true, same_site: :lax }
        token
      end
    end

    def entry_params
      params.require(:trip_entry).permit(
        :title, :description, :latitude, :longitude, :occurred_at,
        :manual_location, :manual_time
      )
    end

    def attach_photos(entry)
      Array(params[:photos]).each_with_index do |file, index|
        next if file.blank?
        entry.photos.create!(uploaded_by: Current.user, position: entry.photos.count + index, image: file)
      end
    end
end
