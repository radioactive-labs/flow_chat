module UssdEngine
  module Middleware
    class RequestId
      def initialize(app)
        @app = app
      end

      def call(context)
        context["ussd_engine.request"][:id] = get_request_identifier(context) if context["ussd_engine.request"].present?
        @app.call(context)
      end

      private

      def get_request_identifier(context)
        File.join(
          context["PATH_INFO"],
          (Config.resumable_sessions_enabled && Config.resumable_sessions_global) ? "global" : context["ussd_engine.request"][:provider].to_s,
          context["ussd_engine.request"][:msisdn]
        )
      end
    end
  end
end
