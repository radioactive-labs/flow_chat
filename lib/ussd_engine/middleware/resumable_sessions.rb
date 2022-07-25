module UssdEngine
  module Middleware
    class ResumableSessions
      def initialize(app)
        @app = app
      end

      def call(env)
        if Config.resumable_sessions_enabled && env["ussd_engine.request"].present?
          request = Rack::Request.new(env)
          session = request.session

          env["ussd_engine.resumable_sessions"] = {}

          # If this is a new session but we have the flag set, this means the call terminated before
          # the session closed. Force it to resume.
          # This is safe since a new session is started if the old session does not indeed exist.
          if env["ussd_engine.request"][:type] == :initial && can_resume_session?(session)
            env["ussd_engine.request"][:type] = :response
            env["ussd_engine.resumable_sessions"][:resumed] = true
          end

          res = @app.call(env)

          if env["ussd_engine.response"].present?
            if env["ussd_engine.response"][:type] == :terminal || env["ussd_engine.resumable_sessions"][:disable]
              session.delete "ussd_engine.resumable_sessions"
            else
              session["ussd_engine.resumable_sessions"] = Time.now.to_i
            end
          end

          res
        else
          @app.call(env)
        end
      end

      private

      def can_resume_session?(session)
        return unless session["ussd_engine.resumable_sessions"].present?
        return true unless Config.resumable_sessions_timeout_seconds

        last_active_at = Time.at(session["ussd_engine.resumable_sessions"])
        return (Time.now - Config.resumable_sessions_timeout_seconds) < last_active_at
      end
    end
  end
end
