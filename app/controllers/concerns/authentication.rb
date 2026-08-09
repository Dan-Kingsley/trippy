module Authentication
  extend ActiveSupport::Concern

  included do
    # Most of Trippy is browsable by anonymous visitors (public trips, private
    # trips unlocked by code). Individual controllers opt into requiring a
    # session (require_authentication) or adventurer role (require_adventurer).
    before_action :resume_session
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      Current.user.present?
    end

    def require_authentication
      resume_session || request_authentication
    end

    def require_adventurer
      require_authentication
      unless performed? || Current.user&.adventurer?
        redirect_to root_path, alert: "You need adventurer access for that."
      end
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    def find_session_by_cookie
      Session.find_by(id: cookies.signed[:session_id]) if cookies.signed[:session_id]
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || root_url
    end

    def start_new_session_for(user)
      user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.session = session
        cookies.signed.permanent[:session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
