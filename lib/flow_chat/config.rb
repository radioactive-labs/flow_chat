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
    mattr_accessor :inject_middleware_logger, default: defined?(Rails) && Rails.env.development?

    # Called with the turn's context and the error when a gateway cannot
    # deliver a reply the flow produced, before the error is re-raised.
    #
    # For the app that owns the turn, acting on records only it knows about: a
    # gateway sends after the middleware stack has returned, so an app that
    # recorded the reply has already recorded it as sent, and nothing
    # downstream of the send can tell it otherwise.
    #
    # The whole context, because this is the app's own code reading what the
    # app put there. Anything wanting only to watch deliveries fail should
    # subscribe to message.delivery_failed instead, which carries no more than
    # a successful send announces.
    #
    # Raising here would replace the delivery error with this one, so an
    # exception is logged and dropped.
    mattr_accessor :on_delivery_failure, default: nil

    # Called with (context, result) once a reply has actually been delivered,
    # where result is whatever the platform's client returned. The mirror of
    # on_delivery_failure, and the only place an app can learn the id the platform
    # gave a message: gateways deliver after the middleware stack has unwound, so
    # a row written during the turn does not yet know it.
    #
    # Every gateway that delivers out of band names that id the same way, on the
    # context as "delivery.platform_message_id", so an app does not have to know
    # the shape of each platform's answer.
    #
    # Raising here would replace a successful send with an error, so an exception
    # is logged and dropped.
    mattr_accessor :on_delivery_success, default: nil

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

    # Messenger-specific configuration object
    def self.messenger
      @messenger ||= MessengerConfig.new
    end

    class SessionConfig
      attr_accessor :boundaries, :hash_identifiers, :identifier, :session_id_proc

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

        # Proc for custom session ID generation (overrides default behavior when set)
        @session_id_proc = nil
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
        @api_base_url = "https://graph.facebook.com/v23.0"
      end
    end

    class MessengerConfig
      attr_reader :api_base_url, :max_text_length, :max_quick_replies,
        :max_quick_reply_title, :max_carousel_elements, :max_buttons_per_element,
        :max_button_title, :max_element_title

      def initialize
        @api_base_url = "https://graph.facebook.com/v23.0"
        @max_text_length = 2000
        @max_quick_replies = 13
        @max_quick_reply_title = 20
        @max_carousel_elements = 10
        @max_buttons_per_element = 3
        @max_button_title = 20
        @max_element_title = 80
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
