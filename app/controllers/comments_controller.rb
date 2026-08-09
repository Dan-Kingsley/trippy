class CommentsController < ApplicationController
  before_action :require_authentication
  before_action :set_trip_and_entry

  def create
    unless trip_accessible?(@trip)
      redirect_to root_path, alert: "This trip is private." and return
    end

    comment = @entry.comments.new(comment_params)
    comment.user = Current.user

    if comment.save
      redirect_to trip_trip_entry_path(@trip, @entry)
    else
      redirect_to trip_trip_entry_path(@trip, @entry), alert: comment.errors.full_messages.to_sentence
    end
  end

  def destroy
    comment = @entry.comments.find(params[:id])
    if comment.user_id == Current.user.id || Current.user.can_edit?(@trip) || Current.user.admin?
      comment.destroy
      redirect_to trip_trip_entry_path(@trip, @entry), notice: "Comment removed."
    else
      redirect_to trip_trip_entry_path(@trip, @entry), alert: "You can't remove that comment."
    end
  end

  private
    def set_trip_and_entry
      @trip = Trip.find_by!(slug: params[:trip_slug])
      @entry = @trip.trip_entries.find(params[:trip_entry_id])
    end

    def comment_params
      params.require(:comment).permit(:body, :parent_id)
    end
end
