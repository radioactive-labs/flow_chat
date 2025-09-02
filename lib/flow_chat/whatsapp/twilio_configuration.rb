module FlowChat
  module Whatsapp
    # Configuration-related errors
    class ConfigurationError < StandardError; end

    class TwilioConfiguration
      attr_accessor :account_sid, :auth_token, :phone_number, :name, :skip_signature_validation

      # Class-level storage for named configurations
      @@configurations = {}

      def initialize(name)
        @name = name
        @account_sid = nil
        @auth_token = nil
        @phone_number = nil
        @skip_signature_validation = false

        FlowChat.logger.debug { "Twilio::Configuration: Initialized configuration with name: #{name || "anonymous"}" }

        register_as(name) if name.present?
      end

      # Load configuration from Rails credentials or environment variables
      def self.from_credentials
        FlowChat.logger.info { "Twilio::Configuration: Loading configuration from credentials/environment" }

        config = new(nil)

        if defined?(Rails) && Rails.respond_to?(:application) && Rails.application&.credentials&.twilio_whatsapp
          FlowChat.logger.debug { "Twilio::Configuration: Loading from Rails credentials" }
          credentials = Rails.application.credentials.twilio_whatsapp
          config.account_sid = credentials[:account_sid]
          config.auth_token = credentials[:auth_token]
          config.phone_number = credentials[:phone_number]
          config.skip_signature_validation = credentials[:skip_signature_validation] || false
        else
          FlowChat.logger.debug { "Twilio::Configuration: Loading from environment variables" }
          # Fallback to environment variables
          config.account_sid = ENV["TWILIO_ACCOUNT_SID"]
          config.auth_token = ENV["TWILIO_AUTH_TOKEN"]
          config.phone_number = ENV["TWILIO_WHATSAPP_PHONE_NUMBER"]
          config.skip_signature_validation = ENV["TWILIO_WHATSAPP_SKIP_SIGNATURE_VALIDATION"] == "true"
        end

        if config.valid?
          FlowChat.logger.info { "Twilio::Configuration: Configuration loaded successfully - phone_number: #{config.phone_number}" }
        else
          FlowChat.logger.warn { "Twilio::Configuration: Incomplete configuration loaded - missing required fields" }
        end

        config
      end

      # Register a named configuration
      def self.register(name, config)
        FlowChat.logger.debug { "Twilio::Configuration: Registering configuration '#{name}'" }
        @@configurations[name.to_sym] = config
      end

      # Get a named configuration
      def self.get(name)
        config = @@configurations[name.to_sym]
        if config
          FlowChat.logger.debug { "Twilio::Configuration: Retrieved configuration '#{name}'" }
          config
        else
          FlowChat.logger.error { "Twilio::Configuration: Configuration '#{name}' not found" }
          raise ArgumentError, "Twilio WhatsApp configuration '#{name}' not found"
        end
      end

      # Check if a named configuration exists
      def self.exists?(name)
        exists = @@configurations.key?(name.to_sym)
        FlowChat.logger.debug { "Twilio::Configuration: Configuration '#{name}' exists: #{exists}" }
        exists
      end

      # Get all configuration names
      def self.configuration_names
        names = @@configurations.keys
        FlowChat.logger.debug { "Twilio::Configuration: Available configurations: #{names}" }
        names
      end

      # Clear all registered configurations (useful for testing)
      def self.clear_all!
        FlowChat.logger.debug { "Twilio::Configuration: Clearing all registered configurations" }
        @@configurations.clear
      end

      # Register this configuration with a name
      def register_as(name)
        FlowChat.logger.debug { "Twilio::Configuration: Registering configuration as '#{name}'" }
        @name = name.to_sym
        self.class.register(@name, self)
        self
      end

      def valid?
        is_valid = account_sid && !account_sid.to_s.empty? &&
          auth_token && !auth_token.to_s.empty? &&
          phone_number && !phone_number.to_s.empty?

        FlowChat.logger.debug { "Twilio::Configuration: Configuration valid: #{is_valid}" }
        is_valid
      end

      # API base URL for Twilio
      def api_base_url
        "https://api.twilio.com"
      end

      # Messages API endpoint
      def messages_url
        "#{api_base_url}/2010-04-01/Accounts/#{account_sid}/Messages.json"
      end

      # Headers for API requests
      def api_headers
        auth_string = Base64.strict_encode64("#{account_sid}:#{auth_token}")
        {
          "Authorization" => "Basic #{auth_string}",
          "Content-Type" => "application/x-www-form-urlencoded"
        }
      end
    end
  end
end
