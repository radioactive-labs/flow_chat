module FlowChat
  module Telegram
    class Configuration
      attr_accessor :bot_token, :secret_token, :name, :skip_signature_validation

      @@configurations = {}

      def initialize(name)
        @name = name
        @bot_token = nil
        @secret_token = nil
        @skip_signature_validation = false

        FlowChat.logger.debug { "Telegram::Configuration: Initialized configuration with name: #{name || "anonymous"}" }

        register_as(name) if name.present?
      end

      def self.from_credentials
        FlowChat.logger.info { "Telegram::Configuration: Loading configuration from credentials/environment" }

        config = new(nil)

        if defined?(Rails) && Rails.respond_to?(:application) && Rails.application.credentials.telegram
          FlowChat.logger.debug { "Telegram::Configuration: Loading from Rails credentials" }
          credentials = Rails.application.credentials.telegram
          config.bot_token = credentials[:bot_token]
          config.secret_token = credentials[:secret_token]
          config.skip_signature_validation = credentials[:skip_signature_validation] || false
        else
          FlowChat.logger.debug { "Telegram::Configuration: Loading from environment variables" }
          config.bot_token = ENV["TELEGRAM_BOT_TOKEN"]
          config.secret_token = ENV["TELEGRAM_SECRET_TOKEN"]
          config.skip_signature_validation = ENV["TELEGRAM_SKIP_SIGNATURE_VALIDATION"] == "true"
        end

        if config.valid?
          FlowChat.logger.info { "Telegram::Configuration: Configuration loaded successfully" }
        else
          FlowChat.logger.warn { "Telegram::Configuration: Incomplete configuration loaded - missing required fields" }
        end

        config
      end

      def self.register(name, config)
        FlowChat.logger.debug { "Telegram::Configuration: Registering configuration '#{name}'" }
        @@configurations[name.to_sym] = config
      end

      def self.get(name)
        config = @@configurations[name.to_sym]
        if config
          FlowChat.logger.debug { "Telegram::Configuration: Retrieved configuration '#{name}'" }
          config
        else
          FlowChat.logger.error { "Telegram::Configuration: Configuration '#{name}' not found" }
          raise ArgumentError, "Telegram configuration '#{name}' not found"
        end
      end

      def self.exists?(name)
        exists = @@configurations.key?(name.to_sym)
        FlowChat.logger.debug { "Telegram::Configuration: Configuration '#{name}' exists: #{exists}" }
        exists
      end

      def self.configuration_names
        names = @@configurations.keys
        FlowChat.logger.debug { "Telegram::Configuration: Available configurations: #{names}" }
        names
      end

      def self.clear_all!
        FlowChat.logger.debug { "Telegram::Configuration: Clearing all registered configurations" }
        @@configurations.clear
      end

      def register_as(name)
        FlowChat.logger.debug { "Telegram::Configuration: Registering configuration as '#{name}'" }
        @name = name.to_sym
        self.class.register(@name, self)
        self
      end

      def valid?
        is_valid = !!(bot_token && !bot_token.to_s.empty?)
        FlowChat.logger.debug { "Telegram::Configuration: Configuration valid: #{is_valid}" }
        is_valid
      end

      def api_base_url
        return nil unless bot_token
        "https://api.telegram.org/bot#{bot_token}"
      end

      def bot_id
        bot_token&.split(":")&.first
      end

      def send_message_url
        "#{api_base_url}/sendMessage"
      end

      def set_webhook_url
        "#{api_base_url}/setWebhook"
      end

      def get_webhook_info_url
        "#{api_base_url}/getWebhookInfo"
      end

      def delete_webhook_url
        "#{api_base_url}/deleteWebhook"
      end
    end
  end
end
