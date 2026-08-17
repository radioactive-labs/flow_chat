module FlowChat
  module Intercom
    class Configuration
      include FlowChat::NamedConfiguration

      attr_accessor :access_token, :client_secret, :admin_id, :name, :skip_signature_validation

      def initialize(name)
        @name = name
        @access_token = nil
        @client_secret = nil
        @admin_id = nil
        @skip_signature_validation = false

        FlowChat.logger.debug { "Intercom::Configuration: Initialized configuration with name: #{name || "anonymous"}" }

        register_as(name) if name.present?
      end

      # Load configuration from Rails credentials or environment variables
      def self.from_credentials
        FlowChat.logger.info { "Intercom::Configuration: Loading configuration from credentials/environment" }

        config = new(nil)

        if defined?(Rails) && Rails.application.credentials.intercom
          FlowChat.logger.debug { "Intercom::Configuration: Loading from Rails credentials" }
          credentials = Rails.application.credentials.intercom
          config.access_token = credentials[:access_token]
          config.client_secret = credentials[:client_secret]
          config.admin_id = credentials[:admin_id]
          config.skip_signature_validation = credentials[:skip_signature_validation] || false
        else
          FlowChat.logger.debug { "Intercom::Configuration: Loading from environment variables" }
          # Fallback to environment variables
          config.access_token = ENV["INTERCOM_ACCESS_TOKEN"]
          config.client_secret = ENV["INTERCOM_CLIENT_SECRET"]
          config.admin_id = ENV["INTERCOM_ADMIN_ID"]
          config.skip_signature_validation = ENV["INTERCOM_SKIP_SIGNATURE_VALIDATION"] == "true"
        end

        if config.valid?
          FlowChat.logger.info { "Intercom::Configuration: Configuration loaded successfully" }
        else
          FlowChat.logger.warn { "Intercom::Configuration: Incomplete configuration loaded - missing required fields" }
        end

        config
      end

      def valid?
        is_valid = !!(access_token && !access_token.to_s.empty? && admin_id && !admin_id.to_s.empty?)

        FlowChat.logger.debug { "Intercom::Configuration: Configuration valid: #{is_valid}" }
        is_valid
      end

      # API endpoints
      def api_base_url
        "https://api.intercom.io"
      end

      def conversations_url(conversation_id = nil)
        if conversation_id
          "#{api_base_url}/conversations/#{conversation_id}"
        else
          "#{api_base_url}/conversations"
        end
      end

      def conversation_reply_url(conversation_id)
        "#{conversations_url(conversation_id)}/reply"
      end

      def conversation_parts_url(conversation_id)
        "#{conversations_url(conversation_id)}/parts"
      end

      def conversation_tags_url(conversation_id, tag_id = nil)
        if tag_id
          "#{conversations_url(conversation_id)}/tags/#{tag_id}"
        else
          "#{conversations_url(conversation_id)}/tags"
        end
      end

      def admins_url
        "#{api_base_url}/admins"
      end

      # Headers for API requests
      def api_headers
        {
          "Authorization" => "Bearer #{access_token}",
          "Content-Type" => "application/json",
          "Accept" => "application/json",
          "Intercom-Version" => "2.11"
        }
      end
    end
  end
end
