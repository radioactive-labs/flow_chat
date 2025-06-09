module FlowChat
  module Ussd
    class Processor < FlowChat::BaseProcessor
      def use_durable_sessions(cross_gateway: false)
        FlowChat.logger.debug { "Ussd::Processor: Enabling durable sessions via session configuration" }
        use_session_config(
          identifier: :msisdn  # Use MSISDN for durable sessions
        )
      end

      protected

      def middleware_name
        "ussd.middleware"
      end

      def build_middleware_stack
        FlowChat.logger.debug { "Ussd::Processor: Building USSD middleware stack" }
        create_middleware_stack("ussd")
      end

      def configure_middleware_stack(builder)
        FlowChat.logger.debug { "Ussd::Processor: Configuring USSD middleware stack" }

        builder.use FlowChat::Ussd::Middleware::Pagination
        FlowChat.logger.debug { "Ussd::Processor: Added Ussd::Middleware::Pagination" }

        builder.use middleware
        FlowChat.logger.debug { "Ussd::Processor: Added custom middleware" }

        builder.use FlowChat::Ussd::Middleware::ChoiceMapper
        FlowChat.logger.debug { "Ussd::Processor: Added Ussd::Middleware::ChoiceMapper" }

        builder.use FlowChat::Ussd::Middleware::Executor
        FlowChat.logger.debug { "Ussd::Processor: Added Ussd::Middleware::Executor" }
      end
    end
  end
end
