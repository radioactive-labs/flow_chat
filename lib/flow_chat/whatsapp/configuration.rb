module FlowChat
  module Whatsapp
    class Configuration
      attr_accessor :access_token, :phone_number_id, :verify_token, :app_id, :app_secret,
        :webhook_verify_token, :business_account_id, :name, :skip_signature_validation

      # Class-level storage for named configurations
      @@configurations = {}

      def initialize(name)
        @name = name
        @access_token = nil
        @phone_number_id = nil
        @verify_token = nil
        @app_id = nil
        @app_secret = nil
        @webhook_verify_token = nil
        @business_account_id = nil
        @skip_signature_validation = false

        FlowChat.logger.debug { "WhatsApp::Configuration: Initialized configuration with name: #{name || 'anonymous'}" }

        register_as(name) if name.present?
      end

      # Load configuration from Rails credentials or environment variables
      def self.from_credentials
        FlowChat.logger.info { "WhatsApp::Configuration: Loading configuration from credentials/environment" }
        
        config = new(nil)

        if defined?(Rails) && Rails.application.credentials.whatsapp
          FlowChat.logger.debug { "WhatsApp::Configuration: Loading from Rails credentials" }
          credentials = Rails.application.credentials.whatsapp
          config.access_token = credentials[:access_token]
          config.phone_number_id = credentials[:phone_number_id]
          config.verify_token = credentials[:verify_token]
          config.app_id = credentials[:app_id]
          config.app_secret = credentials[:app_secret]
          config.business_account_id = credentials[:business_account_id]
          config.skip_signature_validation = credentials[:skip_signature_validation] || false
        else
          FlowChat.logger.debug { "WhatsApp::Configuration: Loading from environment variables" }
          # Fallback to environment variables
          config.access_token = ENV["WHATSAPP_ACCESS_TOKEN"]
          config.phone_number_id = ENV["WHATSAPP_PHONE_NUMBER_ID"]
          config.verify_token = ENV["WHATSAPP_VERIFY_TOKEN"]
          config.app_id = ENV["WHATSAPP_APP_ID"]
          config.app_secret = ENV["WHATSAPP_APP_SECRET"]
          config.business_account_id = ENV["WHATSAPP_BUSINESS_ACCOUNT_ID"]
          config.skip_signature_validation = ENV["WHATSAPP_SKIP_SIGNATURE_VALIDATION"] == "true"
        end

        if config.valid?
          FlowChat.logger.info { "WhatsApp::Configuration: Configuration loaded successfully - phone_number_id: #{config.phone_number_id}" }
        else
          FlowChat.logger.warn { "WhatsApp::Configuration: Incomplete configuration loaded - missing required fields" }
        end

        config
      end

      # Register a named configuration
      def self.register(name, config)
        FlowChat.logger.debug { "WhatsApp::Configuration: Registering configuration '#{name}'" }
        @@configurations[name.to_sym] = config
      end

      # Get a named configuration
      def self.get(name)
        config = @@configurations[name.to_sym]
        if config
          FlowChat.logger.debug { "WhatsApp::Configuration: Retrieved configuration '#{name}'" }
          config
        else
          FlowChat.logger.error { "WhatsApp::Configuration: Configuration '#{name}' not found" }
          raise ArgumentError, "WhatsApp configuration '#{name}' not found"
        end
      end

      # Check if a named configuration exists
      def self.exists?(name)
        exists = @@configurations.key?(name.to_sym)
        FlowChat.logger.debug { "WhatsApp::Configuration: Configuration '#{name}' exists: #{exists}" }
        exists
      end

      # Get all configuration names
      def self.configuration_names
        names = @@configurations.keys
        FlowChat.logger.debug { "WhatsApp::Configuration: Available configurations: #{names}" }
        names
      end

      # Clear all registered configurations (useful for testing)
      def self.clear_all!
        FlowChat.logger.debug { "WhatsApp::Configuration: Clearing all registered configurations" }
        @@configurations.clear
      end

      # Register this configuration with a name
      def register_as(name)
        FlowChat.logger.debug { "WhatsApp::Configuration: Registering configuration as '#{name}'" }
        @name = name.to_sym
        self.class.register(@name, self)
        self
      end

      def valid?
        is_valid = access_token && !access_token.to_s.empty? && 
                   phone_number_id && !phone_number_id.to_s.empty? && 
                   verify_token && !verify_token.to_s.empty?
        
        FlowChat.logger.debug { "WhatsApp::Configuration: Configuration valid: #{is_valid}" }
        is_valid
      end

      # API endpoints
      def messages_url
        "#{FlowChat::Config.whatsapp.api_base_url}/#{phone_number_id}/messages"
      end

      def media_url(media_id)
        "#{FlowChat::Config.whatsapp.api_base_url}/#{media_id}"
      end

      def phone_numbers_url
        "#{FlowChat::Config.whatsapp.api_base_url}/#{business_account_id}/phone_numbers"
      end

      # Get API base URL from global config
      def api_base_url
        FlowChat::Config.whatsapp.api_base_url
      end

      # Headers for API requests
      def api_headers
        {
          "Authorization" => "Bearer #{access_token}",
          "Content-Type" => "application/json"
        }
      end
    end
  end
end
