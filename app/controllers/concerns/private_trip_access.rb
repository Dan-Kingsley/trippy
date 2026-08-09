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
      return true if unlocked_trip_codes.include?(trip.secret_code)
      Current.user && Current.user.can_edit?(trip)
    end
end
