module FlowChat
  module Whatsapp
    module Middleware
      class Executor
        def initialize(app)
          @app = app
          FlowChat.logger.debug { "Whatsapp::Executor: Initialized WhatsApp executor middleware" }
        end

        def call(context)
          flow_class = context.flow
          action = context["flow.action"]
          session_id = context["session.id"]

          FlowChat.logger.info { "Whatsapp::Executor: Executing flow #{flow_class.name}##{action} for session #{session_id}" }

          whatsapp_app = build_whatsapp_app context
          FlowChat.logger.debug { "Whatsapp::Executor: WhatsApp app built for flow execution" }

          flow = flow_class.new whatsapp_app
          FlowChat.logger.debug { "Whatsapp::Executor: Flow instance created, invoking #{action} method" }

          flow.send action
          FlowChat.logger.warn { "Whatsapp::Executor: Flow execution failed to interact with user for #{flow_class.name}##{action}" }
          raise FlowChat::Interrupt::Terminate, "Unexpected end of flow."
        rescue FlowChat::Interrupt::Prompt => e
          FlowChat.logger.info { "Whatsapp::Executor: Flow prompted user - Session: #{session_id}, Prompt: '#{e.prompt.truncate(100)}'" }
          FlowChat.logger.debug { "Whatsapp::Executor: Prompt details - Choices: #{e.choices&.size || 0}, Has media: #{!e.media.nil?}" }
          # Return the same triplet format as USSD for consistency
          [:prompt, e.prompt, e.choices, e.media]
        rescue FlowChat::Interrupt::Terminate => e
          FlowChat.logger.info { "Whatsapp::Executor: Flow terminated - Session: #{session_id}, Message: '#{e.prompt.truncate(100)}'" }
          FlowChat.logger.debug { "Whatsapp::Executor: Destroying session #{session_id}" }
          # Clean up session and return terminal message
          context.session.destroy
          [:terminate, e.prompt, nil, e.media]
        rescue => error
          FlowChat.logger.error { "Whatsapp::Executor: Flow execution failed - #{flow_class.name}##{action}, Session: #{session_id}, Error: #{error.class.name}: #{error.message}" }
          FlowChat.logger.debug { "Whatsapp::Executor: Stack trace: #{error.backtrace.join("\n")}" }
          raise
        end

        private

        def build_whatsapp_app(context)
          FlowChat.logger.debug { "Whatsapp::Executor: Building WhatsApp app instance" }
          FlowChat::Whatsapp::App.new(context)
        end
      end
    end
  end
end
