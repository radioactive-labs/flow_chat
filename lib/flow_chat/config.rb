module FlowChat
  module Config
    # General framework configuration
    mattr_accessor :logger, default: Logger.new($stdout)
    mattr_accessor :cache, default: nil
    mattr_accessor :simulator_secret, default: nil
    # When true (default), validation errors are combined with the original message.
    # When false, only the validation error message is shown to the user.
    mattr_accessor :combine_validation_error_with_message, default: true
    # When true, inject logger into middleware stack. Defaults to true in Rails development.
    mattr_accessor :inject_middleware_logger, default: (defined?(Rails) && Rails.env.development?)

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

    # HTTP-specific configuration object
    def self.http
      @http ||= HttpConfig.new
    end

    class SessionConfig
      attr_accessor :boundaries, :hash_identifiers, :identifier

      def initialize
        # Session boundaries control how session IDs are constructed
        # :flow = separate sessions per flow
        # :gateway = separate sessions per gateway
        # :platform = separate sessions per platform (ussd, whatsapp)
        @boundaries = [:flow, :gateway, :platform]

        # Always hash phone numbers for privacy
        @hash_identifiers = true

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
      attr_reader :api_base_url

      def initialize
        @api_base_url = "https://graph.facebook.com/v22.0"
      end
    end

    class HttpConfig
      attr_accessor :default_gateway, :request_timeout, :response_format

      def initialize
        @default_gateway = :simple
        @request_timeout = 30
        @response_format = :json
      end
    end
  end

  # Shorthand for accessing the logger throughout the application
  def self.logger
    Config.logger
  end
end
