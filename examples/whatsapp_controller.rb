# Example WhatsApp Controller
# Add this to your Rails application as app/controllers/whatsapp_controller.rb

# Basic WhatsApp controller using Rails credentials
class WhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Whatsapp::Processor.new(self, enable_simulator: Rails.env.development?) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  rescue => e
    Rails.logger.error "Error processing WhatsApp webhook: #{e.message}"
    head :internal_server_error
  end
end

# Controller with custom configuration
class CustomWhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    custom_config = build_whatsapp_config

    processor = FlowChat::Whatsapp::Processor.new(self, enable_simulator: !Rails.env.production?) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, custom_config
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  rescue => e
    Rails.logger.error "Error processing WhatsApp webhook: #{e.message}"
    head :internal_server_error
  end

  private

  def build_whatsapp_config
    config = FlowChat::Whatsapp::Configuration.new

    case Rails.env
    when "development", "test"
      config.access_token = ENV["WHATSAPP_ACCESS_TOKEN"]
      config.phone_number_id = ENV["WHATSAPP_PHONE_NUMBER_ID"]
      config.verify_token = ENV["WHATSAPP_VERIFY_TOKEN"]
      config.app_secret = ENV["WHATSAPP_APP_SECRET"]
      config.skip_signature_validation = true  # Skip for easier development

    when "staging", "production"
      config.access_token = ENV["WHATSAPP_ACCESS_TOKEN"]
      config.phone_number_id = ENV["WHATSAPP_PHONE_NUMBER_ID"]
      config.verify_token = ENV["WHATSAPP_VERIFY_TOKEN"]
      config.app_secret = ENV["WHATSAPP_APP_SECRET"]
      config.skip_signature_validation = false  # Always validate in production

      if config.app_secret.blank?
        raise "WHATSAPP_APP_SECRET required for signature validation in #{Rails.env}"
      end
    end

    config
  end
end

# Example flow for WhatsApp
class WelcomeFlow < FlowChat::Flow
  def main_page
    name = app.screen(:name) do |prompt|
      prompt.ask "Hello! What's your name?",
        transform: ->(input) { input.strip.titleize }
    end

    choice = app.screen(:main_menu) do |prompt|
      prompt.select "Hi #{name}! How can I help?", {
        "info" => "📋 Get Information",
        "support" => "🆘 Contact Support",
        "feedback" => "💬 Give Feedback"
      }
    end

    case choice
    when "info"
      show_info
    when "support"
      contact_support
    when "feedback"
      collect_feedback
    end
  end

  private

  def show_info
    app.say "📍 Located at 123 Main Street\n🕒 Hours: Mon-Fri 9AM-6PM\n📞 Call: (555) 123-4567"
  end

  def contact_support
    method = app.screen(:contact_method) do |prompt|
      prompt.select "How would you like to contact us?", {
        "call" => "📞 Call Us",
        "email" => "📧 Email Us"
      }
    end

    case method
    when "call"
      app.say "📞 Call us at (555) 123-4567"
    when "email"
      app.say "📧 Email us at support@example.com"
    end
  end

  def collect_feedback
    rating = app.screen(:rating) do |prompt|
      prompt.select "Rate our service:", ["⭐", "⭐⭐", "⭐⭐⭐", "⭐⭐⭐⭐", "⭐⭐⭐⭐⭐"]
    end

    feedback = app.screen(:feedback_text) do |prompt|
      prompt.ask "Any additional comments?"
    end

    save_feedback(app.phone_number, rating, feedback)
    app.say "Thank you for your feedback! 🙏"
  end

  def save_feedback(phone, rating, feedback)
    Rails.logger.info "Feedback from #{phone}: #{rating} - #{feedback}"
    # Add your feedback saving logic here
  end
end

# Add this route to your config/routes.rb:
# post '/whatsapp/webhook', to: 'whatsapp#webhook'
