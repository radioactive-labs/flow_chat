module FlowChat
  module Instagram
    # Its own file so Zeitwerk can resolve it by name. See the note on
    # FlowChat::Messenger::ConfigurationError.
    class ConfigurationError < StandardError; end
  end
end
