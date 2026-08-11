module FlowChat
  module Intercom
    # Its own file so Zeitwerk can resolve it by name. Declared inside
    # client.rb and gateway/intercom_api.rb, which Zeitwerk maps to a different constant, it existed only
    # once that file had loaded for some other reason, so an application
    # rescuing it, or a test naming it first, got an uninitialized constant.
    class ConfigurationError < StandardError; end
  end
end
