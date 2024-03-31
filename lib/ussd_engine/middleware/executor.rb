module UssdEngine
  module Middleware
    class Executor
      def initialize(app)
        @app = app
      end

      def call(context)
        context.controller.instance_variable_set :@ussd_app, ussd_app(context)
        context.controller.send context["request.action"]
      rescue UssdEngine::Processor::Prompt => e
        [:prompt, e.prompt, e.choices]
      rescue UssdEngine::Processor::Terminate => e
        [:terminate, e.prompt, nil]
      end

      private

      def ussd_app(context)
        UssdEngine::App.new(context)
      end
    end
  end
end
