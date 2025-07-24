require "net/http"
require "json"
require "uri"
require "securerandom"

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

      def initialize(config)
        @config = config
        FlowChat.logger.info { "Intercom::Client: Initialized Intercom client" }
        FlowChat.logger.debug { "Intercom::Client: API base URL: #{@config.api_base_url}" }
      end

      # Send a reply to a conversation
      # @param conversation_id [String] Conversation ID
      # @param response [Array] FlowChat response array [type, content, options]
      # @return [Hash] API response or nil on error
      def send_message(conversation_id, response)
        type, content, _ = response
        FlowChat.logger.info { "Intercom::Client: Sending #{type} message to conversation #{conversation_id}" }
        FlowChat.logger.debug { "Intercom::Client: Message content: '#{content.to_s.truncate(100)}'" }

        result = instrument(Events::MESSAGE_SENT, {
          to: conversation_id,
          message_type: type.to_s,
          content_length: content.to_s.length,
          platform: :intercom
        }) do
          message_data = build_reply_payload(response, conversation_id)
          send_api_request(:post, @config.conversation_reply_url(conversation_id), message_data)
        end

        if result
          message_id = result["id"]
          FlowChat.logger.debug { "Intercom::Client: Message sent successfully to conversation #{conversation_id}, message_id: #{message_id}" }
        else
          FlowChat.logger.error { "Intercom::Client: Failed to send message to conversation #{conversation_id}" }
        end

        result
      end

      # Send a text reply to a conversation
      # @param conversation_id [String] Conversation ID
      # @param text [String] Message text
      # @return [Hash] API response or nil on error
      def reply_to_conversation(conversation_id, text)
        FlowChat.logger.debug { "Intercom::Client: Sending text reply to conversation #{conversation_id}" }
        send_message(conversation_id, [:text, text, {}])
      end

      # Assign a conversation to an admin or team
      # @param conversation_id [String] Conversation ID
      # @param assignee_id [String] Admin ID to assign to (use 0 to unassign)
      # @param team_id [String] Optional team ID
      # @return [Hash] API response or nil on error
      def assign_conversation(conversation_id, assignee_id, team_id: nil)
        FlowChat.logger.info { "Intercom::Client: Assigning conversation #{conversation_id} to admin #{assignee_id}" }
        FlowChat.logger.debug { "Intercom::Client: Team ID: #{team_id}" } if team_id

        assignment_data = {
          message_type: "assignment",
          type: "admin"
        }

        # Set assignee (0 means unassign)
        if assignee_id.to_s == "0"
          assignment_data[:assignee_id] = 0
          FlowChat.logger.debug { "Intercom::Client: Unassigning conversation from human agents" }
        else
          assignment_data[:admin_id] = assignee_id.to_s
        end

        # Set team if provided
        assignment_data[:team_id] = team_id.to_s if team_id

        result = instrument(Events::CONVERSATION_ASSIGNED, {
          conversation_id: conversation_id,
          assignee_id: assignee_id,
          team_id: team_id,
          platform: :intercom
        }) do
          send_api_request(:post, @config.conversation_reply_url(conversation_id), assignment_data)
        end

        if result
          FlowChat.logger.debug { "Intercom::Client: Conversation assignment successful" }
        else
          FlowChat.logger.error { "Intercom::Client: Failed to assign conversation #{conversation_id}" }
        end

        result
      end

      # Unassign a conversation from all admins
      # @param conversation_id [String] Conversation ID
      # @return [Hash] API response or nil on error
      def unassign_conversation(conversation_id)
        FlowChat.logger.info { "Intercom::Client: Unassigning conversation #{conversation_id}" }
        assign_conversation(conversation_id, "0")
      end

      # Add a tag to a conversation
      # @param conversation_id [String] Conversation ID
      # @param tag_name [String] Tag name to add
      # @return [Hash] API response or nil on error
      def add_tag(conversation_id, tag_name)
        FlowChat.logger.info { "Intercom::Client: Adding tag '#{tag_name}' to conversation #{conversation_id}" }

        tag_data = {
          name: tag_name
        }

        result = instrument(Events::CONVERSATION_TAGGED, {
          conversation_id: conversation_id,
          tag_name: tag_name,
          action: "add",
          platform: :intercom
        }) do
          send_api_request(:post, @config.conversation_tags_url(conversation_id), tag_data)
        end

        if result
          FlowChat.logger.debug { "Intercom::Client: Tag '#{tag_name}' added successfully" }
        else
          FlowChat.logger.error { "Intercom::Client: Failed to add tag '#{tag_name}' to conversation #{conversation_id}" }
        end

        result
      end

      # Remove a tag from a conversation
      # @param conversation_id [String] Conversation ID
      # @param tag_id [String] Tag ID to remove
      # @return [Hash] API response or nil on error
      def remove_tag(conversation_id, tag_id)
        FlowChat.logger.info { "Intercom::Client: Removing tag #{tag_id} from conversation #{conversation_id}" }

        result = instrument(Events::CONVERSATION_TAGGED, {
          conversation_id: conversation_id,
          tag_id: tag_id,
          action: "remove",
          platform: :intercom
        }) do
          send_api_request(:delete, @config.conversation_tags_url(conversation_id, tag_id))
        end

        if result
          FlowChat.logger.debug { "Intercom::Client: Tag #{tag_id} removed successfully" }
        else
          FlowChat.logger.error { "Intercom::Client: Failed to remove tag #{tag_id} from conversation #{conversation_id}" }
        end

        result
      end

      # Update conversation state (open, closed, snoozed) and/or priority
      # @param conversation_id [String] Conversation ID
      # @param state [String, nil] New state: "open", "closed", or "snoozed" (nil to skip state change)
      # @param priority [String, nil] Priority: "priority" or "not_priority" (nil to skip priority change)
      # @param snoozed_until [Time] When to reopen if snoozed
      # @return [Hash] API response or nil on error
      def update_conversation_state(conversation_id, state = nil, priority: nil, snoozed_until: nil)
        FlowChat.logger.info { "Intercom::Client: Updating conversation #{conversation_id}" }
        FlowChat.logger.debug { "Intercom::Client: State: #{state}, Priority: #{priority}, Snoozed until: #{snoozed_until}" }

        state_data = {}

        # Add state if specified
        if state
          state_data[:message_type] = state

          # Add snooze time if state is snoozed
          if state == "snoozed" && snoozed_until
            state_data[:snoozed_until] = snoozed_until.to_i
          end
        end

        # Add priority if specified
        state_data[:priority] = priority if priority

        # Return early if nothing to update
        return true if state_data.empty?

        result = instrument(Events::CONVERSATION_STATE_CHANGED, {
          conversation_id: conversation_id,
          state: state,
          priority: priority,
          platform: :intercom
        }) do
          send_api_request(:post, @config.conversation_reply_url(conversation_id), state_data)
        end

        if result
          FlowChat.logger.debug { "Intercom::Client: Conversation updated successfully" }
        else
          FlowChat.logger.error { "Intercom::Client: Failed to update conversation #{conversation_id}" }
        end

        result
      end

      # Get conversation details
      # @param conversation_id [String] Conversation ID
      # @return [Hash] Conversation data or nil on error
      def get_conversation(conversation_id)
        FlowChat.logger.debug { "Intercom::Client: Retrieving conversation #{conversation_id}" }

        result = send_api_request(:get, @config.conversations_url(conversation_id))

        if result
          FlowChat.logger.debug { "Intercom::Client: Conversation retrieved successfully" }
        else
          FlowChat.logger.error { "Intercom::Client: Failed to retrieve conversation #{conversation_id}" }
        end

        result
      end

      # List all admins in the workspace
      # This is useful for finding admin IDs to use in configuration
      # @return [Hash] Admins list or nil on error
      def list_admins
        FlowChat.logger.debug { "Intercom::Client: Retrieving admins list" }

        result = send_api_request(:get, @config.admins_url)

        if result
          FlowChat.logger.debug { "Intercom::Client: Admins list retrieved successfully" }
          if result["admins"]
            FlowChat.logger.info { "Intercom::Client: Found #{result["admins"].length} admins" }
            result["admins"].each do |admin|
              FlowChat.logger.info { "  - #{admin["name"]} (#{admin["email"]}) - ID: #{admin["id"]}" }
            end
          end
        else
          FlowChat.logger.error { "Intercom::Client: Failed to retrieve admins list" }
        end

        result
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

      private

      # Send API request to Intercom
      # @param method [Symbol] HTTP method (:get, :post, :put, :delete)
      # @param url [String] API endpoint URL
      # @param data [Hash] Request data (for POST/PUT)
      # @return [Hash] API response or nil on error
      def send_api_request(method, url, data = nil)
        FlowChat.logger.debug { "Intercom::Client: Sending #{method.upcase} request to #{url}" }

        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = case method
        when :get
          Net::HTTP::Get.new(uri)
        when :post
          req = Net::HTTP::Post.new(uri)
          req.body = data.to_json if data
          req
        when :put
          req = Net::HTTP::Put.new(uri)
          req.body = data.to_json if data
          req
        when :delete
          Net::HTTP::Delete.new(uri)
        else
          raise ArgumentError, "Unsupported HTTP method: #{method}"
        end

        # Set headers
        @config.api_headers.each do |key, value|
          request[key] = value
        end

        FlowChat.logger.debug { "Intercom::Client: Making HTTP request to Intercom API" }
        response = http.request(request)

        case response.code.to_i
        when 200..299
          result = JSON.parse(response.body)
          FlowChat.logger.debug { "Intercom::Client: API request successful" }
          result
        when 401
          FlowChat.logger.error { "Intercom::Client: Authentication failed - check access token" }
          raise ConfigurationError, "Invalid Intercom access token"
        when 403
          FlowChat.logger.error { "Intercom::Client: Forbidden - insufficient permissions" }
          raise ConfigurationError, "Insufficient permissions for Intercom API"
        when 404
          FlowChat.logger.error { "Intercom::Client: Resource not found - #{response.body}" }
          nil
        when 429
          retry_after = response["Retry-After"]&.to_i || 60
          FlowChat.logger.warn { "Intercom::Client: Rate limit exceeded - retry after #{retry_after}s" }
          raise RateLimitError.new("Intercom API rate limit exceeded", retry_after)
        when 500..599
          FlowChat.logger.error { "Intercom::Client: Server error - #{response.code}: #{response.body}" }
          nil
        else
          FlowChat.logger.error { "Intercom::Client: API request failed - #{response.code}: #{response.body}" }
          nil
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => network_error
        # Let network timeouts bubble up for proper error handling
        FlowChat.logger.error { "Intercom::Client: Network timeout: #{network_error.class.name}: #{network_error.message}" }
        raise network_error
      rescue JSON::ParserError => json_error
        FlowChat.logger.error { "Intercom::Client: Invalid JSON response: #{json_error.message}" }
        nil
      rescue ConfigurationError, RateLimitError
        # Re-raise specific errors
        raise
      rescue => error
        FlowChat.logger.error { "Intercom::Client: API request exception: #{error.class.name}: #{error.message}" }
        nil
      end
    end
  end
end
