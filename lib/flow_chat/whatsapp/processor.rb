module FlowChat
  module Whatsapp
    class Processor < FlowChat::BaseProcessor
      def use_whatsapp_config(config)
        @whatsapp_config = config
        self
      end

      def use_gateway(gateway_class)
        if gateway_class == FlowChat::Whatsapp::Gateway::CloudApi
          @gateway = @whatsapp_config ? gateway_class.new(nil, @whatsapp_config) : gateway_class.new(nil)
        else
          @gateway = gateway_class.new(nil)
        end
        self
      end

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