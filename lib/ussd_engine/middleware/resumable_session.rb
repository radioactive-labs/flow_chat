module UssdEngine
  module Middleware
    class ResumableSession
      def initialize(app)
        @app = app
      end

      def call(context)
        if Config.resumable_sessions_enabled && context["ussd_engine.request"].present?
          request = Rack::Request.new(context)
          session = request.session

          context["ussd_engine.resumable_sessions"] = {}

          # If this is a new session but we have the flag set, this means the call terminated before
          # the session closed. Force it to resume.
          # This is safe since a new session is started if the old session does not indeed exist.
          if context["ussd_engine.request"][:type] == :initial && can_resume_session?(session)
            context["ussd_engine.request"][:type] = :response
            context["ussd_engine.resumable_sessions"][:resumed] = true
          end

          res = @app.call(context)

          if context["ussd_engine.response"].present?
            if context["ussd_engine.response"][:type] == :terminal || context["ussd_engine.resumable_sessions"][:disable]
              session.delete "ussd_engine.resumable_sessions"
            else
              session["ussd_engine.resumable_sessions"] = Time.now.to_i
            end
          end

          res
        else
          @app.call(context)
        end
      end

      private

      def can_resume_session?(session)
        return unless session["ussd_engine.resumable_sessions"].present?
        return true unless Config.resumable_sessions_timeout_seconds

        last_active_at = Time.at(session["ussd_engine.resumable_sessions"])
        (Time.now - Config.resumable_sessions_timeout_seconds) < last_active_at
      end
    end
  end
end
