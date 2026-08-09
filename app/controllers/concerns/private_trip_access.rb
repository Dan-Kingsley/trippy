module PrivateTripAccess
  extend ActiveSupport::Concern

  COOKIE_KEY = :private_trip_codes

  private
    def unlocked_trip_codes
      Array(cookies.signed[COOKIE_KEY])
    end

    def remember_trip_code!(code)
      codes = (unlocked_trip_codes + [ code ]).uniq
      cookies.signed.permanent[COOKIE_KEY] = { value: codes, httponly: true, same_site: :lax }
    end

    def trip_accessible?(trip)
      return true if trip.public?

      if unlocked_trip_codes.include?(trip.secret_code)
        grant_trip_access!(trip)
        return true
      end

      return false unless Current.user
      Current.user.can_edit?(trip) || trip.trip_accesses.exists?(user_id: Current.user.id)
    end

    # Ties this browser's code-based unlock to the signed-in account, so the
    # trip stays accessible from any of the account's other devices too.
    def grant_trip_access!(trip)
      TripAccess.find_or_create_by(trip: trip, user: Current.user) if Current.user
    end

    # Called right after a session is established (sign-in or sign-up) so that
    # any private trips already unlocked in this browser (via a shared link or
    # a manually entered code) are immediately tied to the account too.
    def grant_unlocked_trip_access!
      return if unlocked_trip_codes.empty?
      Trip.where(public: false, secret_code: unlocked_trip_codes).find_each { |trip| grant_trip_access!(trip) }
    end
end
