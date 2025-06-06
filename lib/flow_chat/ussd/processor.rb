module FlowChat
  module Ussd
    class Processor < FlowChat::BaseProcessor
      def use_resumable_sessions
        FlowChat.logger.debug { "Ussd::Processor: Enabling resumable sessions middleware" }
        middleware.insert_before 0, FlowChat::Ussd::Middleware::ResumableSession
        self
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
        
        builder.use FlowChat::Session::Middleware
        FlowChat.logger.debug { "Ussd::Processor: Added Session::Middleware" }
        
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
