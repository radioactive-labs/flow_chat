module FlowChat
  module TestSupport
    # A minimal stand-in for a Meta gateway: just enough state (@config) and hook
    # overrides for FlowChat::Meta::SignatureValidation to run against directly,
    # without pulling in a full platform gateway. platform_label and
    # configuration_error_class are required by the module, so this fake supplies
    # its own rather than relying on a default.
    class FakeMetaGateway
      include FlowChat::Meta::SignatureValidation

      def initialize(config)
        @config = config
      end

      private

      def configuration_error_class
        FlowChat::Meta::ConfigurationError
      end

      def platform_label
        "FakeMeta"
      end
    end
  end
end
