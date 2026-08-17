module FlowChat
  module Messenger
    # Its own file so Zeitwerk can resolve it by name. Declared inside
    # configuration.rb it existed only once that file had loaded for some other
    # reason, so an application rescuing it, or a test naming it before anything
    # touched the configuration class, got an uninitialized constant instead.
    class ConfigurationError < StandardError; end
  end
end
