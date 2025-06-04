module FlowChat
  module Ussd
    class Processor < FlowChat::BaseProcessor
      def use_resumable_sessions
        middleware.insert_before 0, FlowChat::Ussd::Middleware::ResumableSession
        self
      end

      protected

      def middleware_name
        "ussd.middleware"
      end

      def build_middleware_stack
        create_middleware_stack("ussd")
      end

      def configure_middleware_stack(builder)
        builder.use FlowChat::Session::Middleware
        builder.use FlowChat::Ussd::Middleware::Pagination
        builder.use middleware
        builder.use FlowChat::Ussd::Middleware::Executor
      end
    end
  end
end 