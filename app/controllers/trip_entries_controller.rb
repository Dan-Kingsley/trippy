class TripEntriesController < ApplicationController
  include PhotoUploadable

  before_action :set_trip
  before_action :require_view_access, only: %i[ show ]
  before_action :require_authentication, except: %i[ show ]
  before_action :require_entry_creator, only: %i[ new create ]
  before_action :require_editor, only: %i[ edit update destroy ]
  before_action :set_entry, only: %i[ show edit update destroy ]

  def show
    @editable = Current.user&.can_edit?(@trip) || false

    if @entry.hidden? && !@editable
      redirect_to trip_path(@trip), alert: t("trip_entries.flashes.hidden_alert") and return
    end

    @comments = @entry.comments.where(parent_id: nil).includes(:user, replies: :user).order(:created_at)
    @trip_member = Current.user && @trip.editors.exists?(id: Current.user.id)
    set_adjacent_entries
    record_view!
  end

  def new
    @entry = @trip.trip_entries.new(occurred_at: Time.current, language: Current.user.locale)
  end

  def create
    @entry = @trip.trip_entries.new(entry_params)
    @entry.created_by = Current.user

    if @entry.save
      rejected = attach_uploads(@entry)
      notice = rejected.positive? ? nil : t("trip_entries.flashes.entry_added")
      alert = rejected.positive? ? t("trip_entries.flashes.entry_added_rejected", count: t("counts.file", count: rejected)) : nil
      redirect_to trip_path(@trip), notice: notice, alert: alert
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @entry.update(entry_params)
      rejected = attach_uploads(@entry)
      notice = rejected.positive? ? nil : t("trip_entries.flashes.entry_updated")
      alert = rejected.positive? ? t("trip_entries.flashes.entry_updated_rejected", count: t("counts.file", count: rejected)) : nil
      redirect_to trip_path(@trip), notice: notice, alert: alert
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @entry.destroy
    redirect_to trip_path(@trip), notice: t("trip_entries.flashes.entry_deleted"), status: :see_other
  end

  private
    def set_trip
      @trip = Trip.find_by!(slug: params[:trip_slug])
    end

    def set_entry
      @entry = @trip.trip_entries.find(params[:id])
    end

    # Mirrors the newest-first ordering of the trip's entry list
    # (see trips/show.html.erb), so the header's back/forward arrows
    # step through entries in the same order the list shows them.
    def set_adjacent_entries
      visible = @editable ? @trip.trip_entries : @trip.trip_entries.where(hidden: false)
      ordered = visible.to_a.reverse
      index = ordered.index(@entry)

      @previous_entry = index && ordered[index - 1] if index&.positive?
      @next_entry = index && index < ordered.length - 1 ? ordered[index + 1] : nil
    end

    def require_view_access
      unless trip_accessible?(@trip)
        redirect_to root_path, alert: t("trips.flashes.private_alert")
      end
    end

    def require_editor
      unless performed? || Current.user.can_edit?(@trip)
        redirect_to trip_path(@trip), alert: t("trip_entries.flashes.not_editor")
      end
    end

    def require_entry_creator
      unless performed? || Current.user.can_add_entries?(@trip)
        redirect_to trip_path(@trip), alert: t("trip_entries.flashes.not_entry_creator")
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
        :location_source, :manual_time, :hidden, :language
      ).merge(
        tagged_collaborator_ids: allowed_tagged_collaborator_ids,
        location_photo_id: allowed_location_photo_id
      )
    end

    # Scopes the pickable "use this photo's location" option to photos that
    # actually belong to this entry, so a tampered request can't point the
    # location at another entry's (possibly private) photo. Entries only ever
    # have photos to pick from once they're persisted, so this is a no-op on
    # create.
    def allowed_location_photo_id
      requested = params.dig(:trip_entry, :location_photo_id)
      return nil if requested.blank? || @entry.nil?

      @entry.photos.where(id: requested).pick(:id)
    end

    # Restricts taggable "who else was there?" people to the trip's own
    # owner/collaborators, regardless of what ids a tampered request sends.
    def allowed_tagged_collaborator_ids
      requested = Array(params.dig(:trip_entry, :tagged_collaborator_ids))
      @trip.editors.where(id: requested).ids
    end
end
