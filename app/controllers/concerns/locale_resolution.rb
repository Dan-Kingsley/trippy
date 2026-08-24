module LocaleResolution
  extend ActiveSupport::Concern

  included do
    around_action :switch_locale
  end

  private
    def switch_locale(&action)
      I18n.with_locale(resolved_locale, &action)
    end

    # Signed-in preference beats a signed-out visitor's own override, which
    # beats a best-guess default from their IP, which beats the app default.
    def resolved_locale
      Current.user&.locale ||
        cookies.signed[:locale_override] ||
        IpGeolocator.locale_for(request.remote_ip)
    end
end
