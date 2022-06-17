require "action_dispatch" unless defined?(Rails)
require "redis-session-store"

module UssdEngine
  module Session
    class RedisStore < ::RedisSessionStore
      def initialize(app, options = {})
        # Disable cookies
        options[:cookie_only] = false
        options[:defer] = true

        super app, options
      end

      def extract_session_id(request)
        get_request_identifier(request.env) || super
      end

      private

      def get_request_identifier(env)
        return unless env["ussd_engine.request"].present?

        "#{env["PATH_INFO"]}#{env["ussd_engine.request"][:provider]}/#{env["ussd_engine.request"][:msisdn]}"
      end

      def set_cookie(*)
        raise "This should never be called"
      end
    end
  end
end
