module FlowChat
  module Intercom
    # Generic conversation management utilities
    class ConversationManager
      include FlowChat::Instrumentation

      attr_reader :conversation_id

      def initialize(client, conversation_id)
        @client = client
        @conversation_id = conversation_id
        FlowChat.logger.debug { "Intercom::ConversationManager: Initialized conversation manager for #{@conversation_id}" }
      end

      # Assign conversation to a specific user/bot
      # @param assignee_id [String] User ID to assign to (use "0" to unassign)
      # @param team_id [String] Optional team ID
      # @return [Boolean] Success status
      def assign_conversation(assignee_id, team_id: nil)
        FlowChat.logger.info { "Intercom::ConversationManager: Assigning conversation #{@conversation_id} to #{assignee_id}" }

        begin
          result = @client.assign_conversation(@conversation_id, assignee_id, team_id: team_id)

          if result
            FlowChat.logger.info { "Intercom::ConversationManager: Successfully assigned conversation #{@conversation_id}" }

            instrument(Events::CONVERSATION_ASSIGNED, {
              conversation_id: @conversation_id,
              assignee_id: assignee_id,
              team_id: team_id,
              platform: :intercom
            })

            true
          else
            FlowChat.logger.error { "Intercom::ConversationManager: Failed to assign conversation #{@conversation_id}" }
            false
          end
        rescue => error
          FlowChat.logger.error { "Intercom::ConversationManager: Error assigning conversation #{@conversation_id}: #{error.message}" }
          false
        end
      end

      # Add a tag to the conversation
      # @param tag_name [String] Tag name to add
      # @return [Boolean] Success status
      def add_tag(tag_name)
        FlowChat.logger.debug { "Intercom::ConversationManager: Adding tag '#{tag_name}' to conversation #{@conversation_id}" }

        begin
          result = @client.add_tag(@conversation_id, tag_name)

          if result
            FlowChat.logger.debug { "Intercom::ConversationManager: Successfully added tag '#{tag_name}'" }

            instrument(Events::CONVERSATION_TAGGED, {
              conversation_id: @conversation_id,
              tag_name: tag_name,
              action: "add",
              platform: :intercom
            })

            true
          else
            FlowChat.logger.error { "Intercom::ConversationManager: Failed to add tag '#{tag_name}'" }
            false
          end
        rescue => error
          FlowChat.logger.error { "Intercom::ConversationManager: Error adding tag '#{tag_name}': #{error.message}" }
          false
        end
      end

      # Remove tags from the conversation by name
      # @param tag_names [Array<String>] Tag names to remove
      # @return [Boolean] Success status
      def remove_tags_by_name(tag_names)
        FlowChat.logger.debug { "Intercom::ConversationManager: Removing tags #{tag_names} from conversation #{@conversation_id}" }

        success = true

        begin
          # Get conversation to find tag IDs
          conversation = @client.get_conversation(@conversation_id)
          return false unless conversation

          if conversation["tags"] && conversation["tags"]["tags"]
            conversation["tags"]["tags"].each do |tag|
              if tag_names.include?(tag["name"])
                tag_result = @client.remove_tag(@conversation_id, tag["id"])
                success = false unless tag_result

                if tag_result
                  instrument(Events::CONVERSATION_TAGGED, {
                    conversation_id: @conversation_id,
                    tag_name: tag["name"],
                    tag_id: tag["id"],
                    action: "remove",
                    platform: :intercom
                  })
                end
              end
            end
          end

          if success
            FlowChat.logger.debug { "Intercom::ConversationManager: Successfully removed tags #{tag_names}" }
          else
            FlowChat.logger.error { "Intercom::ConversationManager: Failed to remove some tags" }
          end
        rescue => error
          FlowChat.logger.error { "Intercom::ConversationManager: Error removing tags: #{error.message}" }
          success = false
        end

        success
      end

      # Update conversation state
      # @param state [String] New state: "open", "closed", or "snoozed"
      # @param snoozed_until [Time] When to reopen if snoozed (only for "snoozed" state)
      # @return [Boolean] Success status
      def update_state(state, snoozed_until: nil)
        FlowChat.logger.info { "Intercom::ConversationManager: Updating conversation #{@conversation_id} state to #{state}" }

        begin
          result = @client.update_conversation_state(@conversation_id, state,
            snoozed_until: snoozed_until)

          if result
            FlowChat.logger.info { "Intercom::ConversationManager: Successfully updated conversation state" }

            instrument(Events::CONVERSATION_STATE_CHANGED, {
              conversation_id: @conversation_id,
              state: state,
              platform: :intercom
            })

            true
          else
            FlowChat.logger.error { "Intercom::ConversationManager: Failed to update conversation state" }
            false
          end
        rescue => error
          FlowChat.logger.error { "Intercom::ConversationManager: Error updating conversation state: #{error.message}" }
          false
        end
      end

      # Update conversation priority
      # @param priority [String] Priority: "priority" or "not_priority"
      # @return [Boolean] Success status
      def update_priority(priority)
        FlowChat.logger.info { "Intercom::ConversationManager: Updating conversation #{@conversation_id} priority to #{priority}" }

        begin
          result = @client.update_conversation_state(@conversation_id, nil, priority: priority)

          if result
            FlowChat.logger.info { "Intercom::ConversationManager: Successfully updated conversation priority" }

            instrument(Events::CONVERSATION_STATE_CHANGED, {
              conversation_id: @conversation_id,
              priority: priority,
              platform: :intercom
            })

            true
          else
            FlowChat.logger.error { "Intercom::ConversationManager: Failed to update conversation priority" }
            false
          end
        rescue => error
          FlowChat.logger.error { "Intercom::ConversationManager: Error updating conversation priority: #{error.message}" }
          false
        end
      end

      # Send a reply to the conversation
      # @param message [String] Message content
      # @param type [Symbol] Message type: :text or :note
      # @return [Boolean] Success status
      def send_reply(message, type: :text)
        FlowChat.logger.debug { "Intercom::ConversationManager: Sending #{type} reply to conversation #{@conversation_id}" }

        begin
          result = @client.send_message(@conversation_id, [type, message, {}])

          if result
            FlowChat.logger.debug { "Intercom::ConversationManager: Successfully sent reply" }
            true
          else
            FlowChat.logger.error { "Intercom::ConversationManager: Failed to send reply" }
            false
          end
        rescue => error
          FlowChat.logger.error { "Intercom::ConversationManager: Error sending reply: #{error.message}" }
          false
        end
      end

      # Get conversation details
      # @return [Hash, nil] Conversation data or nil on error
      def get_conversation
        FlowChat.logger.debug { "Intercom::ConversationManager: Retrieving conversation #{@conversation_id}" }

        begin
          conversation = @client.get_conversation(@conversation_id)

          if conversation
            FlowChat.logger.debug { "Intercom::ConversationManager: Successfully retrieved conversation" }
          else
            FlowChat.logger.error { "Intercom::ConversationManager: Failed to retrieve conversation" }
          end

          conversation
        rescue => error
          FlowChat.logger.error { "Intercom::ConversationManager: Error retrieving conversation: #{error.message}" }
          nil
        end
      end

      # Check if conversation has specific tags
      # @param tag_names [Array<String>] Tag names to check for
      # @return [Boolean] True if conversation has any of the specified tags
      def has_tags?(tag_names)
        FlowChat.logger.debug { "Intercom::ConversationManager: Checking if conversation #{@conversation_id} has tags: #{tag_names}" }

        begin
          conversation = get_conversation
          return false unless conversation

          if conversation["tags"] && conversation["tags"]["tags"]
            existing_tag_names = conversation["tags"]["tags"].map { |tag| tag["name"] }
            has_any_tags = (tag_names & existing_tag_names).any?

            FlowChat.logger.debug { "Intercom::ConversationManager: Conversation has tags: #{has_any_tags}" }
            return has_any_tags
          end

          false
        rescue => error
          FlowChat.logger.error { "Intercom::ConversationManager: Error checking tags: #{error.message}" }
          false
        end
      end

      # Get conversation tags
      # @return [Array<String>] Array of tag names
      def get_tags
        FlowChat.logger.debug { "Intercom::ConversationManager: Getting tags for conversation #{@conversation_id}" }

        begin
          conversation = get_conversation
          return [] unless conversation

          if conversation["tags"] && conversation["tags"]["tags"]
            tag_names = conversation["tags"]["tags"].map { |tag| tag["name"] }
            FlowChat.logger.debug { "Intercom::ConversationManager: Found tags: #{tag_names}" }
            return tag_names
          end

          []
        rescue => error
          FlowChat.logger.error { "Intercom::ConversationManager: Error getting tags: #{error.message}" }
          []
        end
      end
    end
  end
end
