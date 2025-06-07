module FlowChat
  module Whatsapp
    class Processor < FlowChat::BaseProcessor
      def use_whatsapp_config(config)
        FlowChat.logger.debug { "Whatsapp::Processor: Configuring WhatsApp config: #{config.class.name}" }
        @whatsapp_config = config
        self
      end

      protected

      def middleware_name
        "whatsapp.middleware"
      end

      def build_middleware_stack
        FlowChat.logger.debug { "Whatsapp::Processor: Building WhatsApp middleware stack" }
        create_middleware_stack("whatsapp")
      end

      def configure_middleware_stack(builder)
        FlowChat.logger.debug { "Whatsapp::Processor: Configuring WhatsApp middleware stack" }
        builder.use FlowChat::Session::Middleware
        FlowChat.logger.debug { "Whatsapp::Processor: Added Session::Middleware" }

        builder.use middleware
        FlowChat.logger.debug { "Whatsapp::Processor: Added custom middleware" }

        builder.use FlowChat::Whatsapp::Middleware::Executor
        FlowChat.logger.debug { "Whatsapp::Processor: Added Whatsapp::Middleware::Executor" }
      end
    end
  end
end
