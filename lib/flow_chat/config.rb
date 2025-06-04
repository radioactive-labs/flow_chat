module FlowChat
  module Config
    # General framework configuration
    mattr_accessor :logger, default: Logger.new($stdout)
    mattr_accessor :cache, default: nil

    # USSD-specific configuration object
    def self.ussd
      @ussd ||= UssdConfig.new
    end

    class UssdConfig
      attr_accessor :pagination_page_size, :pagination_back_option, :pagination_back_text,
                    :pagination_next_option, :pagination_next_text,
                    :resumable_sessions_enabled, :resumable_sessions_global, :resumable_sessions_timeout_seconds

      def initialize
        @pagination_page_size = 140
        @pagination_back_option = "0"
        @pagination_back_text = "Back"
        @pagination_next_option = "#"
        @pagination_next_text = "More"
        @resumable_sessions_enabled = false
        @resumable_sessions_global = true
        @resumable_sessions_timeout_seconds = 300
      end
    end
  end
end
