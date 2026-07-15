# Example controller showing how to use the Intercom gateway
# This controller handles webhooks from Intercom for conversation events

class IntercomController < ApplicationController
  skip_forgery_protection

  # POST /intercom/webhook
  # Handle Intercom webhook notifications for conversation events
  def webhook
    processor = FlowChat::Processor.new(self) do |config|
      # Use Intercom gateway with automatic configuration loading
      config.use_gateway FlowChat::Intercom::Gateway::IntercomApi

      # Use cache-based session storage for longer-lived sessions
      config.use_session_store FlowChat::Session::CacheSessionStore

      # Configure session boundaries - use conversation ID for session isolation
      config.use_session_config(
        boundaries: [:conversation], # Each conversation gets its own session
        identifier: :conversation_id  # Use conversation ID as session key
      )
    end

    # Run the customer support flow
    processor.run CustomerSupportFlow, :handle_conversation
  end
end

# Example flow for handling customer conversations via Intercom
class CustomerSupportFlow < FlowChat::Flow
  def handle_conversation
    # Ask the opening question. The prompt is only shown on the first unanswered
    # turn; once the user replies, screen(:inquiry) returns their stored answer.
    inquiry = app.screen(:inquiry) do |prompt|
      prompt.ask "Hello! I'm here to help you. How can I assist you today?"
    end

    # Categorize the inquiry and provide appropriate response
    category = categorize_inquiry(inquiry)

    case category
    when :technical_support
      handle_technical_support
    when :billing
      handle_billing_inquiry
    when :general
      handle_general_inquiry
    when :escalate
      escalate_to_human("Complex issue requiring human attention")
    else
      app.say "I understand you need help. Let me connect you with one of our team members who can assist you better."
      escalate_to_human("Unrecognized inquiry type")
    end
  end

  private

  def categorize_inquiry(inquiry)
    # Simple keyword-based categorization
    # In a real app, you might use AI/ML for better categorization
    text = inquiry.downcase

    if text.include?("bug") || text.include?("error") || text.include?("not working")
      :technical_support
    elsif text.include?("bill") || text.include?("payment") || text.include?("refund")
      :billing
    elsif text.include?("urgent") || text.include?("important") || text.include?("asap")
      :escalate
    else
      :general
    end
  end

  def handle_technical_support
    solution = app.screen(:tech_solution) do |prompt|
      prompt.select "I can help you with technical issues! What type of problem are you experiencing?", {
        "login" => "Can't log in",
        "performance" => "App is slow",
        "features" => "Feature not working",
        "other" => "Something else"
      }
    end

    case solution
    when "login"
      provide_login_help
    when "performance"
      provide_performance_tips
    when "features"
      provide_feature_help
    when "other"
      escalate_to_human("Technical issue requiring human review")
    end
  end

  def handle_billing_inquiry
    app.say "For billing questions, I'm connecting you with our billing team who can access your account securely."
    escalate_to_human("Billing inquiry", team_id: "billing_team_id")
  end

  def handle_general_inquiry
    satisfaction = app.screen(:satisfaction) do |prompt|
      prompt.select "I hope I was able to help! How would you rate your experience?", {
        "1" => "😞 Poor",
        "2" => "😐 Okay",
        "3" => "😊 Good",
        "4" => "😍 Excellent"
      }
    end

    if satisfaction.to_i >= 3
      app.say "Thank you for the positive feedback! Feel free to reach out if you need anything else."
    else
      app.say "I'm sorry the experience wasn't better. Let me connect you with a team member who can help."
      escalate_to_human("User reported poor experience")
    end
  end

  def provide_login_help
    app.say <<~MESSAGE
      Here are some steps to try for login issues:
      
      1. Make sure you're using the correct email address
      2. Try resetting your password using the "Forgot Password" link
      3. Clear your browser cache and cookies
      4. Try logging in from an incognito/private window
      
      If none of these work, I'll connect you with our technical support team.
    MESSAGE

    still_stuck = app.screen(:login_resolved) do |prompt|
      prompt.yes? "Did these steps help resolve your login issue?"
    end

    unless still_stuck
      escalate_to_human("Login issue not resolved by self-service steps")
    end
  end

  def provide_performance_tips
    app.say <<~MESSAGE
      Here are some tips to improve app performance:
      
      1. Close other browser tabs or apps
      2. Check your internet connection
      3. Try refreshing the page
      4. Update your browser to the latest version
      
      If the problem persists, our technical team can investigate further.
    MESSAGE
  end

  def provide_feature_help
    feature = app.screen(:which_feature) do |prompt|
      prompt.ask "Which feature are you having trouble with? Please describe what you're trying to do."
    end

    app.say "Thanks for the details about #{feature}. Let me connect you with our product team who can provide specific guidance."
    escalate_to_human("Feature support request: #{feature}")
  end

  def escalate_to_human(reason, team_id: nil)
    conversation_id = app.context["request.conversation_id"]

    # Business logic: Use Intercom manager for conversation control
    if app.gateway == :intercom_api
      # Access the gateway's client and manager for escalation
      # This would be implemented by exposing these through the gateway
      app.say "I'm connecting you with one of our team members who can provide more personalized assistance. They'll be with you shortly!"

      # Business logic would handle:
      # - Remove AI_HANDLING tag
      # - Add ESCALATED tag
      # - Assign to appropriate team
      # - Set priority based on reason
      # - Add internal note for context

      FlowChat.logger.info { "CustomerSupportFlow: Escalating conversation #{conversation_id} - Reason: #{reason}" }
    else
      app.say "Let me transfer you to a human agent who can help you further."
    end
  end
end
