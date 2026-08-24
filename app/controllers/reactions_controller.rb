class ReactionsController < ApplicationController
  before_action :require_authentication
  before_action :set_trip_and_entry

  def create
    unless trip_accessible?(@trip)
      redirect_to root_path, alert: t("reactions.flashes.private_alert") and return
    end

    emoji = params[:emoji]
    existing = @entry.reactions.find_by(user: Current.user, emoji: emoji)

    if existing
      existing.destroy
    else
      @entry.reactions.create(user: Current.user, emoji: emoji)
    end

    redirect_to trip_trip_entry_path(@trip, @entry)
  end

  def destroy
    @entry.reactions.where(user: Current.user, id: params[:id]).destroy_all
    redirect_to trip_trip_entry_path(@trip, @entry)
  end

  def users
    unless Current.user.can_edit?(@trip)
      head :forbidden and return
    end

    reactors = @entry.reactions.where(emoji: params[:emoji]).includes(:user).map(&:user)
    render partial: "reactions/reactor_list", locals: { emoji: params[:emoji], reactors: reactors }, layout: false
  end

  private
    def set_trip_and_entry
      @trip = Trip.find_by!(slug: params[:trip_slug])
      @entry = @trip.trip_entries.find(params[:trip_entry_id])
    end
end
