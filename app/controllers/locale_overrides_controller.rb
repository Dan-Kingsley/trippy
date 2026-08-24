# Lets a signed-out visitor override the IP-geolocated default language via
# the flag icon in the header. Deliberately doesn't require authentication -
# this is the signed-out path; if a signed-in user hits it directly the
# cookie is harmlessly set but never consulted (see LocaleResolution, which
# always prefers Current.user.locale).
class LocaleOverridesController < ApplicationController
  def create
    locale = params[:locale]
    if I18n.available_locales.map(&:to_s).include?(locale)
      cookies.signed.permanent[:locale_override] = { value: locale, httponly: true, same_site: :lax }
    end

    redirect_back fallback_location: root_path
  end
end
