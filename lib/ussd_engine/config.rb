require "active_support" unless defined?(Rails)

module UssdEngine
  module Config
    mattr_accessor :logger, default: Logger.new($stdout)

    mattr_accessor :pagination_page_size, default: 120
    mattr_accessor :pagination_back_option, default: "0"
    mattr_accessor :pagination_back_text, default: "Back"
    mattr_accessor :pagination_next_option, default: "#"
    mattr_accessor :pagination_next_text, default: "More"
  end
end
