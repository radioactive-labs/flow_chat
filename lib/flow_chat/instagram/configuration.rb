module FlowChat
  module Instagram
    class Configuration
      include FlowChat::NamedConfiguration

      # :facebook is the Instagram API with Facebook Login: the linked Page
      # speaks through graph.facebook.com. :instagram is the Instagram API
      # with Instagram Login: the Instagram professional account speaks for
      # itself through graph.instagram.com, with no Page in the picture.
      LOGIN_PATHS = [:facebook, :instagram].freeze

      attr_accessor :access_token, :page_id, :instagram_account_id, :verify_token,
        :app_id, :app_secret, :name, :skip_signature_validation
      attr_reader :login

      def initialize(name)
        @name = name
        @access_token = nil
        @page_id = nil
        @instagram_account_id = nil
        @verify_token = nil
        @app_id = nil
        @app_secret = nil
        @skip_signature_validation = false
        @login = :facebook

        FlowChat.logger.debug { "Instagram::Configuration: Initialized configuration with name: #{name || "anonymous"}" }

        register_as(name) if name.present?
      end

      # Rejected rather than coerced: a typo here would otherwise silently
      # pick the wrong host and the wrong account identifier, and fail only
      # once a real send or webhook hits the wrong Meta product.
      def login=(value)
        symbol = value&.to_sym
        unless LOGIN_PATHS.include?(symbol)
          raise ArgumentError, "login must be one of #{LOGIN_PATHS.inspect}, got #{value.inspect}"
        end

        @login = symbol
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
          config.login = (credentials[:login] || "facebook").to_sym
        else
          FlowChat.logger.debug { "Instagram::Configuration: Loading from environment variables" }
          config.access_token = ENV["INSTAGRAM_ACCESS_TOKEN"]
          config.page_id = ENV["INSTAGRAM_PAGE_ID"]
          config.instagram_account_id = ENV["INSTAGRAM_ACCOUNT_ID"]
          config.verify_token = ENV["INSTAGRAM_VERIFY_TOKEN"]
          config.app_id = ENV["INSTAGRAM_APP_ID"]
          config.app_secret = ENV["INSTAGRAM_APP_SECRET"]
          config.skip_signature_validation = ENV["INSTAGRAM_SKIP_SIGNATURE_VALIDATION"] == "true"
          config.login = (ENV["INSTAGRAM_LOGIN"] || "facebook").to_sym
        end

        if config.valid?
          FlowChat.logger.info { "Instagram::Configuration: Configuration loaded successfully - #{config.login} login, account #{config.account_id}" }
        else
          FlowChat.logger.warn { "Instagram::Configuration: Incomplete configuration loaded - missing required fields" }
        end

        config
      end

      def valid?
        # Wrapped so a predicate answers true or false rather than nil, which
        # the bare && chain returns for a missing first field. Intercom and
        # Telegram already do this and pin it in their tests.
        is_valid = !!(access_token && !access_token.to_s.empty? &&
          verify_token && !verify_token.to_s.empty? &&
          account_id && !account_id.to_s.empty?)

        FlowChat.logger.debug { "Instagram::Configuration: Configuration valid: #{is_valid}" }
        is_valid
      end

      # The account this configuration speaks for. On the Facebook Login
      # integration path the webhook entry is keyed on the linked Facebook
      # Page, not the Instagram account, so that is what an inbound event is
      # checked against. On the Instagram Login path there is no linked Page
      # at all, so the Instagram professional account id is the only thing to
      # check against.
      def account_id
        (login == :instagram) ? instagram_account_id : page_id
      end

      def messages_url
        "#{api_base_url}/#{account_id}/messages"
      end

      def attachment_upload_url
        "#{api_base_url}/#{account_id}/message_attachments"
      end

      def api_base_url
        (login == :instagram) ? FlowChat::Config.instagram.instagram_login_api_base_url : FlowChat::Config.instagram.api_base_url
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
