module FlowChat
  module Whatsapp
    class Processor < FlowChat::BaseProcessor
      protected

      def middleware_name
        "whatsapp.middleware"
      end

      def build_middleware_stack
        create_middleware_stack("whatsapp")
      end

      def configure_middleware_stack(builder)
        builder.use gateway
        builder.use FlowChat::Session::Middleware
        builder.use middleware
        builder.use FlowChat::Whatsapp::Middleware::Executor
      end
    end
  end
end 