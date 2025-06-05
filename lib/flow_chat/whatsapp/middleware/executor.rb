module FlowChat
  module Whatsapp
    module Middleware
      class Executor
        def initialize(app)
          @app = app
        end

        def call(context)
          whatsapp_app = build_whatsapp_app context
          flow = context.flow.new whatsapp_app
          flow.send context["flow.action"]
        rescue FlowChat::Interrupt::Prompt => e
          # Return the same triplet format as USSD for consistency
          [:prompt, e.prompt, e.choices, e.media]
        rescue FlowChat::Interrupt::Terminate => e
          # Clean up session and return terminal message
          context.session.destroy
          [:terminate, e.prompt, nil, e.media]
        end

        private

        def build_whatsapp_app(context)
          FlowChat::Whatsapp::App.new(context)
        end
      end
    end
  end
end
