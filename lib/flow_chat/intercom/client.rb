require "intercom"
require "json"

module FlowChat
  module Intercom
    # Configuration-related errors
    class ConfigurationError < StandardError; end

    # Rate limiting error
    class RateLimitError < StandardError
      attr_reader :retry_after

      def initialize(message, retry_after = nil)
        super(message)
        @retry_after = retry_after
      end
    end

    class Client
      include FlowChat::Instrumentation

      attr_reader :intercom

      def initialize(config)
        @config = config
        @intercom = ::Intercom::Client.new(token: @config.access_token)
        FlowChat.logger.info { "Intercom::Client: Initialized Intercom client" }
        FlowChat.logger.debug { "Intercom::Client: API base URL: #{@config.api_base_url}" }
      end

      # Send a reply to a conversation
      # @param conversation_id [String] Conversation ID
      # @param response [Array] FlowChat response array [type, content, options]
      # @return [Hash] API response or nil on error
      def send_message(conversation_id, prompt, choices: nil, media: nil)
        FlowChat.logger.info { "Intercom::Client: Sending message to conversation #{conversation_id}" }
        FlowChat.logger.debug { "Intercom::Client: Message content: '#{prompt.to_s.truncate(100)}'" }

        # Use renderer to convert to structured response
        response = FlowChat::Intercom::Renderer.new(prompt, choices: choices, media: media).render
        type, content, _ = response

        result = instrument(Events::MESSAGE_SENT, {
          to: conversation_id,
          message_type: type.to_s,
          content_length: content.to_s.length,
          platform: :intercom
        }) do
          # Determine message type based on response type
          message_type = case type
          when :note
            "note"
          else
            "comment"
          end

          # Send using official gem
          reply = intercom.conversations.reply(
            id: conversation_id,
            type: "admin",
            admin_id: @config.admin_id.to_s,
            message_type: message_type,
            body: content.to_s
          )

          reply.to_hash
        end

        if result
          message_id = result["id"]
          FlowChat.logger.debug { "Intercom::Client: Message sent successfully to conversation #{conversation_id}, message_id: #{message_id}" }
        else
          FlowChat.logger.error { "Intercom::Client: Failed to send message to conversation #{conversation_id}" }
        end

        result
      rescue ::Intercom::ResourceNotFound => e
        FlowChat.logger.error { "Intercom::Client: Conversation not found: #{e.message}" }
        nil
      rescue ::Intercom::AuthenticationError => e
        FlowChat.logger.error { "Intercom::Client: Authentication failed - check access token" }
        raise ConfigurationError, "Invalid Intercom access token"
      rescue ::Intercom::RateLimitExceeded => e
        retry_after = 60
        FlowChat.logger.warn { "Intercom::Client: Rate limit exceeded - retry after #{retry_after}s" }
        raise RateLimitError.new("Intercom API rate limit exceeded", retry_after)
      rescue ::Intercom::ServerError => e
        FlowChat.logger.error { "Intercom::Client: Server error: #{e.message}" }
        nil
      rescue => e
        FlowChat.logger.error { "Intercom::Client: API request exception: #{e.class.name}: #{e.message}" }
        nil
      end

      # Build reply payload for Intercom API
      # This method is exposed so the gateway can use it for simulator mode
      def build_reply_payload(response, conversation_id)
        type, content, _ = response

        case type
        when :text
          {
            message_type: "comment",
            type: "admin",
            admin_id: @config.admin_id.to_s,
            body: content.to_s
          }
        when :note
          {
            message_type: "note",
            type: "admin",
            admin_id: @config.admin_id.to_s,
            body: content.to_s
          }
        else
          # Default to comment
          {
            message_type: "comment",
            type: "admin",
            admin_id: @config.admin_id.to_s,
            body: content.to_s
          }
        end
      end

    end
  end
end
