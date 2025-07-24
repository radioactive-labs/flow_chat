# Example showing how to use the Intercom client independently
# for conversation management and bot control

# This example shows how to use the Intercom API client and manager
# outside of the FlowChat gateway for direct conversation management

class IntercomApiUsageExample
  def initialize
    # Set up Intercom configuration
    @config = FlowChat::Intercom::Configuration.from_credentials

    # Create client
    @client = FlowChat::Intercom::Client.new(@config)

    # Business-specific constants (user-defined)
    @ai_tag = "AI_HANDLING"
    @escalated_tag = "ESCALATED"
    @admin_id = "your_admin_id_here"  # Replace with actual admin ID from Intercom
  end

  # Example: Take over a conversation for AI handling
  def take_over_conversation(conversation_id)
    puts "Taking over conversation #{conversation_id} for AI handling..."

    # Create conversation manager for this specific conversation
    conversation_manager = FlowChat::Intercom::ConversationManager.new(@client, conversation_id)

    success = true

    # Step 1: Assign to admin or unassign for bot handling
    success &= if @admin_id && @admin_id != "your_admin_id_here"
      conversation_manager.assign_conversation(@admin_id)
    else
      conversation_manager.assign_conversation("0") # Unassign for automatic routing
    end

    # Step 2: Add AI handling tag
    success &= conversation_manager.add_tag(@ai_tag)

    # Step 3: Set priority appropriately
    success &= conversation_manager.update_priority("not_priority")

    if success
      puts "✓ Successfully took over conversation"

      # Send initial AI response
      conversation_manager.send_reply(
        "Hello! I'm an AI assistant here to help you. How can I assist you today?"
      )

    else
      puts "✗ Failed to take over conversation"
    end

    success
  end

  # Example: Escalate conversation to human agents
  def escalate_to_humans(conversation_id, reason = "user_request", team_id: nil)
    puts "Escalating conversation #{conversation_id} to human agents..."
    puts "Reason: #{reason}"

    # Create conversation manager for this specific conversation
    conversation_manager = FlowChat::Intercom::ConversationManager.new(@client, conversation_id)

    success = true

    # Step 1: Remove AI tags
    success &= conversation_manager.remove_tags_by_name([@ai_tag])

    # Step 2: Add escalation tag
    success &= conversation_manager.add_tag(@escalated_tag)

    # Step 3: Assign to human team or unassign for automatic routing
    success &= if team_id
      conversation_manager.assign_conversation("0", team_id: team_id)
    else
      conversation_manager.assign_conversation("0") # Let assignment rules handle it
    end

    # Step 4: Set priority based on reason
    priority = ["urgent", "error"].include?(reason) ? "priority" : "not_priority"
    success &= conversation_manager.update_priority(priority)

    if success
      puts "✓ Successfully escalated to humans"

      # Send handoff message
      conversation_manager.send_reply(
        "I'm connecting you with one of our team members who can provide more specialized help. They'll be with you shortly!"
      )

    else
      puts "✗ Failed to escalate conversation"
    end

    success
  end

  # Example: Handle a conversation programmatically
  def handle_support_conversation(conversation_id, user_message)
    puts "Processing support message: '#{user_message}'"

    # Take over conversation first
    return unless take_over_conversation(conversation_id)

    # Create conversation manager for this specific conversation
    conversation_manager = FlowChat::Intercom::ConversationManager.new(@client, conversation_id)

    # Simple keyword-based response
    response = generate_response(user_message)

    if response[:escalate]
      # Escalate to humans
      escalate_to_humans(conversation_id, reason: response[:reason])
    else
      # Handle with AI - add "bot active" tag to show it's being processed
      conversation_manager.add_tag("BOT_ACTIVE")
      conversation_manager.send_reply(response[:message])

      # If conversation is resolved, close it
      if response[:resolved]
        # Send final message and close
        conversation_manager.send_reply("Is there anything else I can help you with today?")
        conversation_manager.update_state("closed")
      end
    end
  end

  # Example: Batch process multiple conversations
  def process_pending_conversations(conversation_ids)
    puts "Processing #{conversation_ids.length} conversations..."

    conversation_ids.each do |conversation_id|
      # Create conversation manager to check status
      conversation_manager = FlowChat::Intercom::ConversationManager.new(@client, conversation_id)

      # Check if already under bot control
      if conversation_manager.has_tags?([@ai_tag])
        puts "Conversation #{conversation_id} already under bot control, skipping"
        next
      end

      # Get conversation details
      conversation = conversation_manager.get_conversation
      next unless conversation

      # Take over and add initial response
      if take_over_conversation(conversation_id)
        conversation_manager.send_reply(
          "Thank you for contacting us! I'm reviewing your message and will respond shortly."
        )

        puts "✓ Took over conversation #{conversation_id}"
      else
        puts "✗ Failed to take over conversation #{conversation_id}"
      end
    rescue => error
      puts "Error processing conversation #{conversation_id}: #{error.message}"
    end
  end

  # Example: Monitor and manage bot performance
  def generate_daily_report
    puts "Generating daily bot performance report..."

    # This would typically involve querying your database for conversation data
    # and using the Intercom API to get additional details

    report = {
      conversations_handled: 0,
      escalations: 0,
      average_response_time: 0,
      user_satisfaction: 0
    }

    # In a real implementation, you'd:
    # 1. Query conversations tagged with AI_HANDLING_TAG
    # 2. Calculate metrics from conversation data
    # 3. Generate insights and recommendations

    puts "Bot Performance Report:"
    puts "- Conversations handled: #{report[:conversations_handled]}"
    puts "- Escalations to humans: #{report[:escalations]}"
    puts "- Average response time: #{report[:average_response_time]}s"
    puts "- User satisfaction: #{report[:user_satisfaction]}%"
  end

  # Utility: List all admins to help find admin IDs
  def list_admins_for_configuration
    puts "Listing Intercom admins for configuration setup..."

    result = @client.list_admins

    if result && result["admins"]
      puts "\nAvailable admins:"
      puts "-" * 50

      result["admins"].each_with_index do |admin, index|
        status = admin["away_mode_enabled"] ? "(Away)" : "(Active)"
        puts "#{index + 1}. #{admin["name"]} #{status}"
        puts "   Email: #{admin["email"]}"
        puts "   Admin ID: #{admin["id"]}"
        puts
      end

      puts "💡 Copy one of the Admin IDs above and use it in your configuration:"
      puts "   config.admin_id = \"#{result["admins"].first["id"]}\""
    else
      puts "Failed to retrieve admins list"
    end
  end

  private

  def generate_response(message)
    text = message.downcase

    # Simple keyword matching - in production you'd use more sophisticated NLP
    case text
    when /password|login|sign in/
      {
        message: "I can help with login issues! Please try resetting your password using the 'Forgot Password' link. If that doesn't work, I'll connect you with our support team.",
        escalate: false,
        resolved: false
      }
    when /bug|error|broken|not working/
      {
        message: "I understand you're experiencing a technical issue. Let me connect you with our technical support team who can investigate this properly.",
        escalate: true,
        reason: "technical_issue"
      }
    when /billing|payment|refund|charge/
      {
        message: "For billing and payment questions, I'm connecting you with our billing team who can securely access your account information.",
        escalate: true,
        reason: "billing_inquiry"
      }
    when /thank|thanks|resolved|fixed/
      {
        message: "You're welcome! I'm glad I could help. Feel free to reach out if you need anything else.",
        escalate: false,
        resolved: true
      }
    else
      {
        message: "I understand you need assistance. Let me connect you with one of our team members who can provide more specific help.",
        escalate: true,
        reason: "general_inquiry"
      }
    end
  end
end

# Usage examples:
if __FILE__ == $0
  example = IntercomApiUsageExample.new

  # Example conversation ID (replace with actual IDs from your Intercom)
  conversation_id = "123456789"

  puts "=== Intercom API Usage Examples ==="
  puts

  # Example 1: Take over a conversation
  puts "1. Taking over conversation for AI handling:"
  example.take_over_conversation(conversation_id)
  puts

  # Example 2: Process a user message
  puts "2. Processing user message:"
  example.handle_support_conversation(conversation_id, "I forgot my password")
  puts

  # Example 3: Escalate to humans
  puts "3. Escalating conversation to humans:"
  example.escalate_to_humans(conversation_id, "Complex technical issue")
  puts

  # Example 4: Batch processing
  puts "4. Batch processing conversations:"
  example.process_pending_conversations([conversation_id, "987654321"])
  puts

  # Example 5: Generate report
  puts "5. Generating performance report:"
  example.generate_daily_report
  puts

  # Example 6: List admins for configuration
  puts "6. Listing admins for configuration:"
  example.list_admins_for_configuration
end
