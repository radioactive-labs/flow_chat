# Example HTTP Controller for FlowChat HTTP Gateway
#
# This controller demonstrates how to use FlowChat with HTTP requests
# for simple JSON-based conversational interfaces.
#
# Usage:
#   POST /http/webhook
#   Content-Type: application/json
#
#   {
#     "session_id": "unique_session_123",
#     "user_id": "user_456",
#     "input": "Hello"
#   }
#
# Response:
#   {
#     "type": "prompt",
#     "session_id": "unique_session_123",
#     "user_id": "user_456",
#     "timestamp": "2024-01-01T12:00:00Z",
#     "message": "Hello! What's your name?",
#     "choices": [
#       {"key": "1", "text": "Continue"}
#     ]
#   }

class HttpController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Http::Gateway::Simple
      config.use_session_store FlowChat::Session::CacheSessionStore

      # Configure session management
      config.use_session_config(
        boundaries: [:flow, :platform],
        hash_identifiers: true,
        identifier: :msisdn  # Use phone number for durable sessions
      )
    end

    processor.run WelcomeFlow, :main_page
  end
end

# Example flow for HTTP gateway
class WelcomeFlow < FlowChat::Flow
  def main_page
    name = app.screen(:name) do |prompt|
      prompt.ask "Hello! What's your name?",
        validate: ->(input) { "Name is required" if input.blank? },
        transform: ->(input) { input.strip.titleize }
    end

    age = app.screen(:age) do |prompt|
      prompt.ask "Nice to meet you, #{name}! How old are you?",
        validate: ->(input) {
          return "Please enter a number" unless input.match?(/^\d+$/)
          return "Age must be between 1 and 120" unless (1..120).cover?(input.to_i)
          nil
        },
        transform: ->(input) { input.to_i }
    end

    preferences = app.screen(:preferences) do |prompt|
      prompt.select "What are you interested in?", {
        "tech" => "Technology",
        "sports" => "Sports",
        "music" => "Music",
        "travel" => "Travel"
      }
    end

    # Summary
    app.say "Great! Here's what I learned about you:"
    app.say "Name: #{name}"
    app.say "Age: #{age}"
    app.say "Interest: #{preferences.capitalize}"

    # Ask if they want to continue
    continue = app.screen(:continue) do |prompt|
      prompt.yes? "Would you like to explore more features?"
    end

    if continue
      features_demo
    else
      app.say "Thanks for trying FlowChat HTTP Gateway! 👋"
    end
  end

  private

  def features_demo
    choice = app.screen(:feature_choice) do |prompt|
      prompt.select "What would you like to try?", {
        "media" => "Media Support",
        "validation" => "Input Validation",
        "session" => "Session Management"
      }
    end

    case choice
    when "media"
      media_demo
    when "validation"
      validation_demo
    when "session"
      session_demo
    end
  end

  def media_demo
    app.say "FlowChat supports rich media in HTTP responses!",
      media: {
        url: "https://via.placeholder.com/300x200.png?text=FlowChat+HTTP",
        type: :image,
        caption: "FlowChat HTTP Gateway Demo"
      }

    app.say "Media is returned in the JSON response for your frontend to display."
  end

  def validation_demo
    email = app.screen(:email) do |prompt|
      prompt.ask "Enter your email address:",
        validate: ->(input) {
          return "Email is required" if input.blank?
          return "Invalid email format" unless input.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
          nil
        },
        transform: ->(input) { input.downcase.strip }
    end

    app.say "Perfect! Your email #{email} has been validated and normalized."
  end

  def session_demo
    # Store some data in session
    app.session.set("demo_timestamp", Time.current.to_s)
    app.session.set("demo_counter", (app.session.get("demo_counter") || 0) + 1)

    counter = app.session.get("demo_counter")
    timestamp = app.session.get("demo_timestamp")

    app.say "Session Demo:"
    app.say "• This is visit ##{counter} in this session"
    app.say "• Session started at: #{timestamp}"
    app.say "• Session data persists across HTTP requests"
    app.say "• Session ID: #{app.session.context["session.id"]}"
  end
end
