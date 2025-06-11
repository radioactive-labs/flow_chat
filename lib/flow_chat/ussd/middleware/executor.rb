require_relative "../../base_executor"

module FlowChat
  module Ussd
    module Middleware
      class Executor < FlowChat::BaseExecutor
        protected

        def platform_name
          "USSD"
        end

        def log_prefix
          "Ussd::Executor"
        end

        def build_platform_app(context)
          FlowChat.logger.debug { "#{log_prefix}: Building USSD app instance" }
          FlowChat::Ussd::App.new(context)
        end
      end
    end
  end
end
