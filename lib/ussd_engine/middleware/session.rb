module UssdEngine
  module Middleware
    class Session
      def initialize(app)
        @app = app
      end

      def call(context)
        context["session.id"] = session_id context
        context["session"] = context["session.store"].new context
        @app.call(context)
      end

      private

      def session_id(context)
        context["request.id"]
        # File.join(
        #   context["PATH_INFO"],
        #   (Config.resumable_sessions_enabled && Config.resumable_sessions_global) ? "global" : context["ussd_engine.request"][:provider].to_s,
        #   context["ussd_engine.request"][:msisdn]
        # )
      end
    end
  end
end
