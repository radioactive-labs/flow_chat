module FlowChat
  module Meta
    # Raised when a Meta gateway cannot validate a signature because it was not
    # configured to. Platforms override configuration_error_class to raise their own.
    class ConfigurationError < StandardError; end
  end
end
