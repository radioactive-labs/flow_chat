module UssdEngine
  module Middleware
    class RequestId
      def initialize(app)
        @app = app
      end

      def call(env)
        env["ussd_engine.request"][:id] = get_request_identifier(env) if env["ussd_engine.request"].present?
        @app.call(env)
      end

      private

      def get_request_identifier(env)
        File.join(
          env["PATH_INFO"],
          Config.resumable_sessions_enabled && Config.resumable_sessions_global ? "global" : env["ussd_engine.request"][:provider].to_s,
          env["ussd_engine.request"][:msisdn]
        )
      end
    end
  end
end
