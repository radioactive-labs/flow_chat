require_relative "../../base_executor"

module FlowChat
  module Http
    module Middleware
      class Executor < FlowChat::BaseExecutor
        protected

        def platform_name
          "HTTP"
        end

        def log_prefix
          "Http::Executor"
        end

        def build_platform_app(context)
          FlowChat.logger.debug { "#{log_prefix}: Building HTTP app instance" }
          FlowChat::Http::App.new(context)
        end
      end
    end
  end
end 