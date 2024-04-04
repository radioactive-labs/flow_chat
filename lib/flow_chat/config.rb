module FlowChat
  module Config
    mattr_accessor :logger, default: Logger.new($stdout)
    mattr_accessor :cache, default: nil

    mattr_accessor :pagination_page_size, default: 140
    mattr_accessor :pagination_back_option, default: "0"
    mattr_accessor :pagination_back_text, default: "Back"
    mattr_accessor :pagination_next_option, default: "#"
    mattr_accessor :pagination_next_text, default: "More"

    mattr_accessor :resumable_sessions_enabled, default: false
    mattr_accessor :resumable_sessions_global, default: true
    mattr_accessor :resumable_sessions_timeout_seconds, default: 300
  end
end
