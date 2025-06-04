module FlowChat
  module Ussd
    module Middleware
      class ResumableSession
        def initialize(app)
          @app = app
        end

        def call(context)
          if FlowChat::Config.ussd.resumable_sessions_enabled && context["ussd.request"].present?
            # First, try to find any interruption session.
            # The session key can be:
            #  - a global session (key: "global")
            #  - a provider-specific session (key: <provider>)
            session_key = self.class.session_key(context)
            resumable_session = context["session.store"].get(session_key)

            if resumable_session.present? && valid?(resumable_session)
              context.merge! resumable_session
            end
          end

          @app.call(context)
        end

        private

        def valid?(session)
          return true unless FlowChat::Config.ussd.resumable_sessions_timeout_seconds

          last_active_at = Time.parse session.dig("context", "last_active_at")
          (Time.now - FlowChat::Config.ussd.resumable_sessions_timeout_seconds) < last_active_at
        rescue
          false
        end
      end
    end
  end
end
