module FlowChat
  module Http
    class Processor < FlowChat::BaseProcessor
      def use_durable_sessions(cross_gateway: false)
        FlowChat.logger.debug { "Http::Processor: Enabling durable sessions via session configuration" }
        use_session_config(
          identifier: :user_id
        )
      end

      protected

      def middleware_name
        "http.middleware"
      end

      def build_middleware_stack
        FlowChat.logger.debug { "Http::Processor: Building HTTP middleware stack" }
        create_middleware_stack("http")
      end

      def configure_middleware_stack(builder)
        FlowChat.logger.debug { "Http::Processor: Configuring HTTP middleware stack" }

        builder.use middleware
        FlowChat.logger.debug { "Http::Processor: Added custom middleware" }

        builder.use FlowChat::Http::Middleware::Executor
        FlowChat.logger.debug { "Http::Processor: Added Http::Middleware::Executor" }
      end
    end
  end
end 