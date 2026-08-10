module FlowChat
  module Instagram
    class ConfigurationError < StandardError; end

    class Configuration
      include FlowChat::NamedConfiguration

      attr_accessor :access_token, :page_id, :instagram_account_id, :verify_token,
        :app_id, :app_secret, :name, :skip_signature_validation

      def initialize(name)
        @name = name
        @access_token = nil
        @page_id = nil
        @instagram_account_id = nil
        @verify_token = nil
        @app_id = nil
        @app_secret = nil
        @skip_signature_validation = false

        FlowChat.logger.debug { "Instagram::Configuration: Initialized configuration with name: #{name || "anonymous"}" }

        register_as(name) if name.present?
      end

      def self.from_credentials
        FlowChat.logger.info { "Instagram::Configuration: Loading configuration from credentials/environment" }

        config = new(nil)

        if defined?(Rails) && Rails.respond_to?(:application) && Rails.application&.credentials&.instagram
          FlowChat.logger.debug { "Instagram::Configuration: Loading from Rails credentials" }
          credentials = Rails.application.credentials.instagram
          config.access_token = credentials[:access_token]
          config.page_id = credentials[:page_id]
          config.instagram_account_id = credentials[:instagram_account_id]
          config.verify_token = credentials[:verify_token]
          config.app_id = credentials[:app_id]
          config.app_secret = credentials[:app_secret]
          config.skip_signature_validation = credentials[:skip_signature_validation] || false
        else
          FlowChat.logger.debug { "Instagram::Configuration: Loading from environment variables" }
          config.access_token = ENV["INSTAGRAM_ACCESS_TOKEN"]
          config.page_id = ENV["INSTAGRAM_PAGE_ID"]
          config.instagram_account_id = ENV["INSTAGRAM_ACCOUNT_ID"]
          config.verify_token = ENV["INSTAGRAM_VERIFY_TOKEN"]
          config.app_id = ENV["INSTAGRAM_APP_ID"]
          config.app_secret = ENV["INSTAGRAM_APP_SECRET"]
          config.skip_signature_validation = ENV["INSTAGRAM_SKIP_SIGNATURE_VALIDATION"] == "true"
        end

        if config.valid?
          FlowChat.logger.info { "Instagram::Configuration: Configuration loaded successfully - page_id: #{config.page_id}" }
        else
          FlowChat.logger.warn { "Instagram::Configuration: Incomplete configuration loaded - missing required fields" }
        end

        config
      end

      def valid?
        is_valid = access_token && !access_token.to_s.empty? &&
          page_id && !page_id.to_s.empty? &&
          verify_token && !verify_token.to_s.empty?

        FlowChat.logger.debug { "Instagram::Configuration: Configuration valid: #{is_valid}" }
        is_valid
      end

      # The account this configuration speaks for. On the Facebook Login
      # integration path the webhook entry is keyed on the linked Facebook
      # Page, not the Instagram account, so that is what an inbound event is
      # checked against.
      def account_id
        page_id
      end

      def messages_url
        "#{api_base_url}/#{page_id}/messages"
      end

      def attachment_upload_url
        "#{api_base_url}/#{page_id}/message_attachments"
      end

      def api_base_url
        FlowChat::Config.instagram.api_base_url
      end

      def api_headers
        {
          "Authorization" => "Bearer #{access_token}",
          "Content-Type" => "application/json"
        }
      end
    end
  end
end
