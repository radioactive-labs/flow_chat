module FlowChat
  module Messenger
    module Gateway
      # Facebook Messenger, on the shared Messenger Platform envelope.
      class SendApi < FlowChat::Meta::MessagingGateway
        def platform
          :messenger
        end

        def gateway_name
          :messenger_send_api
        end

        def configuration_class
          FlowChat::Messenger::Configuration
        end

        def client_class
          FlowChat::Messenger::Client
        end

        def renderer_class
          FlowChat::Messenger::Renderer
        end

        def self.choice_mapper_class
          FlowChat::Messenger::Middleware::ChoiceMapper
        end

        private

        def configuration_error_class
          FlowChat::Messenger::ConfigurationError
        end

        def platform_label
          "Messenger"
        end
      end
    end
  end
end
