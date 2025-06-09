module FlowChat
  module Config
    # General framework configuration
    mattr_accessor :logger, default: Logger.new($stdout)
    mattr_accessor :cache, default: nil
    mattr_accessor :simulator_secret, default: nil
    # When true (default), validation errors are combined with the original message.
    # When false, only the validation error message is shown to the user.
    mattr_accessor :combine_validation_error_with_message, default: true

    # Session configuration object
    def self.session
      @session ||= SessionConfig.new
    end

    # USSD-specific configuration object
    def self.ussd
      @ussd ||= UssdConfig.new
    end

    # WhatsApp-specific configuration object
    def self.whatsapp
      @whatsapp ||= WhatsappConfig.new
    end

    class SessionConfig
      attr_accessor :boundaries, :hash_phone_numbers, :identifier

      def initialize
        # Session boundaries control how session IDs are constructed
        # :flow = separate sessions per flow
        # :gateway = separate sessions per gateway
        # :platform = separate sessions per platform (ussd, whatsapp)
        @boundaries = [:flow, :gateway, :platform]
        
        # Always hash phone numbers for privacy
        @hash_phone_numbers = true
        
        # Session identifier type (nil = let platforms choose their default)
        # :msisdn = durable sessions (durable across timeouts)
        # :request_id = ephemeral sessions (new session each time)
        @identifier = nil
      end
    end

    class UssdConfig
      attr_accessor :pagination_page_size, :pagination_back_option, :pagination_back_text,
        :pagination_next_option, :pagination_next_text

      def initialize
        @pagination_page_size = 140
        @pagination_back_option = "0"
        @pagination_back_text = "Back"
        @pagination_next_option = "#"
        @pagination_next_text = "More"
      end
    end

    class WhatsappConfig
      attr_accessor :background_job_class
      attr_reader :message_handling_mode, :api_base_url

      def initialize
        @message_handling_mode = :inline
        @background_job_class = "WhatsappMessageJob"
        @api_base_url = "https://graph.facebook.com/v22.0"
      end

      # Validate message handling mode
      def message_handling_mode=(mode)
        valid_modes = [:inline, :background, :simulator]
        unless valid_modes.include?(mode.to_sym)
          raise ArgumentError, "Invalid message handling mode: #{mode}. Valid modes: #{valid_modes.join(", ")}"
        end
        @message_handling_mode = mode.to_sym
      end

      # Helper methods for mode checking
      def inline_mode?
        @message_handling_mode == :inline
      end

      def background_mode?
        @message_handling_mode == :background
      end

      def simulator_mode?
        @message_handling_mode == :simulator
      end
    end
  end

  # Shorthand for accessing the logger throughout the application
  def self.logger
    Config.logger
  end
end
