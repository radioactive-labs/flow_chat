module FlowChat
  module Ussd
    module Middleware
      class Executor
        def initialize(app)
          @app = app
          FlowChat.logger.debug { "Ussd::Executor: Initialized USSD executor middleware" }
        end

        def call(context)
          flow_class = context.flow
          action = context["flow.action"]
          session_id = context["session.id"]

          FlowChat.logger.info { "Ussd::Executor: Executing flow #{flow_class.name}##{action} for session #{session_id}" }

          ussd_app = build_ussd_app context
          FlowChat.logger.debug { "Ussd::Executor: USSD app built for flow execution" }

          flow = flow_class.new ussd_app
          FlowChat.logger.debug { "Ussd::Executor: Flow instance created, invoking #{action} method" }

          flow.send action
          FlowChat.logger.warn { "Ussd::Executor: Flow execution failed to interact with user for #{flow_class.name}##{action}" }
          raise FlowChat::Interrupt::Terminate, "Unexpected end of flow."
        rescue FlowChat::Interrupt::RestartFlow => e
          FlowChat.logger.info { "Ussd::Executor: Flow restart requested - Session: #{session_id}, restarting #{action}" }
          retry
        rescue FlowChat::Interrupt::Prompt => e
          FlowChat.logger.info { "Ussd::Executor: Flow prompted user - Session: #{session_id}, Prompt: '#{e.prompt.truncate(100)}'" }
          FlowChat.logger.debug { "Ussd::Executor: Prompt details - Choices: #{e.choices&.size || 0}, Has media: #{!e.media.nil?}" }
          [:prompt, e.prompt, e.choices, e.media]
        rescue FlowChat::Interrupt::Terminate => e
          FlowChat.logger.info { "Ussd::Executor: Flow terminated - Session: #{session_id}, Message: '#{e.prompt.truncate(100)}'" }
          FlowChat.logger.debug { "Ussd::Executor: Destroying session #{session_id}" }
          context.session.destroy
          [:terminate, e.prompt, nil, e.media]
        rescue => error
          FlowChat.logger.error { "Ussd::Executor: Flow execution failed - #{flow_class.name}##{action}, Session: #{session_id}, Error: #{error.class.name}: #{error.message}" }
          FlowChat.logger.debug { "Ussd::Executor: Stack trace: #{error.backtrace.join("\n")}" }
          raise
        end

        private

        def build_ussd_app(context)
          FlowChat.logger.debug { "Ussd::Executor: Building USSD app instance" }
          FlowChat::Ussd::App.new(context)
        end
      end
    end
  end
end
