module FlowChat
  module Whatsapp
    class Configuration
      attr_accessor :access_token, :phone_number_id, :verify_token, :app_id, :app_secret,
        :webhook_verify_token, :business_account_id, :name

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

        register_as(name) if name.present?
      end

      # Load configuration from Rails credentials or environment variables
      def self.from_credentials
        config = new(nil)

        if defined?(Rails) && Rails.application.credentials.whatsapp
          credentials = Rails.application.credentials.whatsapp
          config.access_token = credentials[:access_token]
          config.phone_number_id = credentials[:phone_number_id]
          config.verify_token = credentials[:verify_token]
          config.app_id = credentials[:app_id]
          config.app_secret = credentials[:app_secret]
          config.business_account_id = credentials[:business_account_id]
        else
          # Fallback to environment variables
          config.access_token = ENV["WHATSAPP_ACCESS_TOKEN"]
          config.phone_number_id = ENV["WHATSAPP_PHONE_NUMBER_ID"]
          config.verify_token = ENV["WHATSAPP_VERIFY_TOKEN"]
          config.app_id = ENV["WHATSAPP_APP_ID"]
          config.app_secret = ENV["WHATSAPP_APP_SECRET"]
          config.business_account_id = ENV["WHATSAPP_BUSINESS_ACCOUNT_ID"]
        end

        config
      end

      # Register a named configuration
      def self.register(name, config)
        @@configurations[name.to_sym] = config
      end

      # Get a named configuration
      def self.get(name)
        @@configurations[name.to_sym] || raise(ArgumentError, "WhatsApp configuration '#{name}' not found")
      end

      # Check if a named configuration exists
      def self.exists?(name)
        @@configurations.key?(name.to_sym)
      end

      # Get all configuration names
      def self.configuration_names
        @@configurations.keys
      end

      # Clear all registered configurations (useful for testing)
      def self.clear_all!
        @@configurations.clear
      end

      # Register this configuration with a name
      def register_as(name)
        @name = name.to_sym
        self.class.register(@name, self)
        self
      end

      def valid?
        access_token && !access_token.to_s.empty? && phone_number_id && !phone_number_id.to_s.empty? && verify_token && !verify_token.to_s.empty?
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
