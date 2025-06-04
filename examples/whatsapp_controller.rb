# Example WhatsApp Controller
# Add this to your Rails application as app/controllers/whatsapp_controller.rb

class WhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Whatsapp::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      # Use cache-based session store for longer WhatsApp conversations
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end

# Example Flow for WhatsApp
# Add this to your Rails application as app/flow_chat/welcome_flow.rb

class WelcomeFlow < FlowChat::Flow
  def main_page
    # Welcome the user
    name = app.screen(:name) do |prompt|
      prompt.ask "Hello! Welcome to our WhatsApp service. What's your name?",
        transform: ->(input) { input.strip.titleize }
    end

    # Show main menu
    choice = app.screen(:main_menu) do |prompt|
      prompt.select "Hi #{name}! What can I help you with today?", {
        "info" => "📋 Get Information",
        "support" => "🆘 Contact Support", 
        "feedback" => "💬 Give Feedback"
      }
    end

    case choice
    when "info"
      show_information_menu
    when "support"
      contact_support
    when "feedback"
      collect_feedback
    end
  end

  private

  def show_information_menu
    info_choice = app.screen(:info_menu) do |prompt|
      prompt.select "What information do you need?", {
        "hours" => "🕒 Business Hours",
        "location" => "📍 Our Location",
        "services" => "🛠 Our Services"
      }
    end

    case info_choice
    when "hours"
      app.say "We're open Monday-Friday 9AM-6PM, Saturday 9AM-2PM. Closed Sundays."
    when "location"
      app.say "📍 We're located at 123 Main Street, City, State 12345"
    when "services"
      app.say "Here are our main services:\\n\\n🌐 Web Development - Custom websites and applications\\n📱 Mobile Apps - iOS and Android development\\n🔧 Consulting - Technical consulting services"
    end
  end

  def contact_support
    # Use standard select menu instead of send_buttons
    contact_method = app.screen(:contact_method) do |prompt|
      prompt.select "How would you like to contact support?", {
        "call" => "📞 Call Us",
        "email" => "📧 Email Us", 
        "chat" => "💬 Live Chat"
      }
    end

    case contact_method
    when "call"
      app.say "📞 You can call us at (555) 123-4567"
    when "email"
      app.say "📧 Send us an email at support@example.com"
    when "chat"
      app.say "💬 Our live chat is available on our website: www.example.com"
    end
  end

  def collect_feedback
    rating = app.screen(:rating) do |prompt|
      prompt.select "How would you rate our service?", {
        "5" => "⭐⭐⭐⭐⭐ Excellent",
        "4" => "⭐⭐⭐⭐ Good", 
        "3" => "⭐⭐⭐ Average",
        "2" => "⭐⭐ Poor",
        "1" => "⭐ Very Poor"
      }
    end

    feedback = app.screen(:feedback_text) do |prompt|
      prompt.ask "Thank you for the #{rating}-star rating! Please share any additional feedback:"
    end

    # Save feedback (implement your logic here)
    save_feedback(app.phone_number, rating, feedback)

    app.say "Thank you for your feedback! We really appreciate it. 🙏"
  end

  def save_feedback(phone, rating, feedback)
    # Implement your feedback saving logic here
    Rails.logger.info "Feedback from #{phone}: #{rating} stars - #{feedback}"
  end
end

# Add this route to your config/routes.rb:
# post '/whatsapp/webhook', to: 'whatsapp#webhook' 