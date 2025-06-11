require_relative "../../base_executor"

module FlowChat
  module Whatsapp
    module Middleware
      class Executor < FlowChat::BaseExecutor
        protected

        def platform_name
          "WhatsApp"
        end

        def log_prefix
          "Whatsapp::Executor"
        end

        def build_platform_app(context)
          FlowChat.logger.debug { "#{log_prefix}: Building WhatsApp app instance" }
          FlowChat::Whatsapp::App.new(context)
        end
      end
    end
  end
end
