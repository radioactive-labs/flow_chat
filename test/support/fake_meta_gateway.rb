module FlowChat
  module TestSupport
    # A minimal stand-in for a Meta gateway: just enough state (@config,
    # @controller) and identity hook overrides for FlowChat::Meta::SignatureValidation
    # and FlowChat::Meta::WebhookVerification to run against directly, without
    # pulling in a full platform gateway. platform, platform_label and
    # configuration_error_class are required by GatewayIdentity, so this fake
    # supplies its own rather than relying on the NotImplementedError defaults.
    class FakeMetaGateway
      include FlowChat::Instrumentation
      include FlowChat::Meta::SignatureValidation
      include FlowChat::Meta::WebhookVerification

      def initialize(config, controller: nil)
        @config = config
        @controller = controller
      end

      private

      def platform
        :fake_meta
      end

      def configuration_error_class
        FlowChat::Meta::ConfigurationError
      end

      def platform_label
        "FakeMeta"
      end
    end
  end
end
