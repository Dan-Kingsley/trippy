require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Trippy
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    config.active_storage.variant_processor = :vips
    config.time_zone = "UTC"

    config.i18n.available_locales = [ :en, :de ]
    config.i18n.default_locale = :en
    # A key missed in a non-default locale file degrades to English text
    # instead of raising/blank, since keys are added incrementally over time.
    config.i18n.fallbacks = true

    # Serve attachments directly through the app instead of redirecting to a
    # separately-expiring signed storage URL - one fewer network hop (which
    # matters on patchy mobile connections) and no more possibility of that
    # redirect's short-lived URL expiring before the browser follows it.
    config.active_storage.resolve_model_to_route = :rails_storage_proxy
  end
end
