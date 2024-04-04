module FlowChat
  module Ussd
    module Middleware
      class Executor
        def initialize(app)
          @app = app
        end

        def call(context)
          ussd_app = build_ussd_app context
          flow = context.flow.new ussd_app
          flow.send context["flow.action"]
        rescue FlowChat::Interrupt::Prompt => e
          [:prompt, e.prompt, e.choices]
        rescue FlowChat::Interrupt::Terminate => e
          context.session.destroy
          [:terminate, e.prompt, nil]
        end

        private

        def build_ussd_app(context)
          FlowChat::Ussd::App.new(context)
        end
      end
    end
  end
end
