require "net/http"
require "json"

# Resolves a default UI locale from a visitor's IP address via a third-party
# geolocation lookup, so signed-out visitors from Germany see German by
# default. Never allowed to slow down or break a page render: any failure,
# timeout, or unexpected response falls back to English immediately, and
# results (including failures) are cached by IP so repeat visits stay well
# under the upstream free-tier rate limit.
class IpGeolocator
  ENDPOINT = "http://ip-api.com/json/%s?fields=countryCode"
  OPEN_TIMEOUT = 1 # second
  READ_TIMEOUT = 1 # second
  CACHE_TTL = 12.hours
  DEFAULT_LOCALE = "en"
  COUNTRY_LOCALES = { "DE" => "de", "AT" => "de", "CH" => "de" }.freeze

  def self.locale_for(ip)
    new(ip).locale
  end

  def initialize(ip)
    @ip = ip
  end

  def locale
    return DEFAULT_LOCALE if @ip.blank? || local_ip?

    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { fetch_locale }
  rescue => e
    Rails.logger.warn("IpGeolocator: unexpected failure for #{@ip}: #{e.class} #{e.message}")
    DEFAULT_LOCALE
  end

  private
    def cache_key = "ip_geolocator/locale/#{@ip}"

    def local_ip?
      @ip == "127.0.0.1" || @ip == "::1" || @ip.start_with?("10.", "192.168.", "172.")
    end

    def fetch_locale
      uri = URI(ENDPOINT % @ip)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      response = http.get(uri)
      return DEFAULT_LOCALE unless response.is_a?(Net::HTTPSuccess)

      country_code = JSON.parse(response.body)["countryCode"]
      COUNTRY_LOCALES.fetch(country_code, DEFAULT_LOCALE)
    rescue Timeout::Error, SocketError, JSON::ParserError => e
      Rails.logger.warn("IpGeolocator: lookup failed for #{@ip}: #{e.class}")
      DEFAULT_LOCALE
    end
end
