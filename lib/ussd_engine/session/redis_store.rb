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

      def current_session_id(request)
        get_request_identifier(request.env) || super
      end

      private

      def get_request_identifier(env)
        return unless env["ussd_engine.request"].present?

        env["ussd_engine.request"][:id]
      end

      def set_cookie(*)
        raise "This should never be called"
      end

      def session_default_values(sid)
        [sid, USE_INDIFFERENT_ACCESS ? {}.with_indifferent_access : {}]
      end

      def get_session(env, sid)
        sid && (session = load_session_from_redis(sid)) ? [sid, session] : session_default_values(sid)
      rescue Errno::ECONNREFUSED, Redis::CannotConnectError => e
        on_redis_down.call(e, env, sid) if on_redis_down
        session_default_values(sid)
      end

      alias find_session get_session
    end
  end
end
