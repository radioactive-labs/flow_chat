# USSD Setup Guide

This guide covers USSD configuration and implementation patterns for FlowChat.

## Basic Setup

### 1. Create a Flow

Create a flow in `app/flow_chat/welcome_flow.rb`:

```ruby
class WelcomeFlow < FlowChat::Flow
  def main_page
    name = app.screen(:name) do |prompt|
      prompt.ask "Welcome! What's your name?",
        transform: ->(input) { input.strip.titleize }
    end

    service = app.screen(:service) do |prompt|
      prompt.select "Choose a service:", {
        "balance" => "Check Balance",
        "transfer" => "Transfer Money",
        "history" => "Transaction History"
      }
    end

    case service
    when "balance"
      show_balance
    when "transfer"
      transfer_money
    when "history"
      show_history
    end
  end

  private

  def show_balance
    # Simulate balance check
    balance = fetch_user_balance(app.phone_number)
    app.say "Hello #{app.session.get(:name)}! Your balance is $#{balance}."
  end
end
```

### 2. Create Controller

```ruby
class UssdController < ApplicationController
  skip_forgery_protection

  def process_request
    processor = FlowChat::Ussd::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end
```

### 3. Configure Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  post 'ussd' => 'ussd#process_request'
end
```

## Gateway Configuration

### Nalo Gateway

FlowChat currently supports Nalo USSD gateways:

```ruby
processor = FlowChat::Ussd::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::CacheSessionStore
end
```

The Nalo gateway expects these parameters in the request:
- `msisdn` - User's phone number
- `input` - User's input text
- `session_id` - Session identifier

## Pagination

USSD messages are automatically paginated when they exceed character limits:

```ruby
# Configure pagination behavior
FlowChat::Config.ussd.pagination_page_size = 140        # characters per page
FlowChat::Config.ussd.pagination_next_option = "#"      # option for next page
FlowChat::Config.ussd.pagination_next_text = "More"     # text for next option
FlowChat::Config.ussd.pagination_back_option = "0"      # option for previous page
FlowChat::Config.ussd.pagination_back_text = "Back"     # text for back option
```

### Example Long Message

```ruby
def show_terms
  terms = "Very long terms and conditions text that exceeds 140 characters..."
  app.say terms  # Automatically paginated
end
```

**USSD Output:**
```
Terms and Conditions:
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt...

# More
0 Back
```

## Session Management

Configure session behavior for better user experience:

```ruby
processor = FlowChat::Ussd::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::CacheSessionStore
  
  # Enable durable sessions (shorthand)
  config.use_durable_sessions
end
```

### Session Boundaries

Session boundaries control how session IDs are constructed:

- **`:flow`** - Separate sessions per flow class
- **`:platform`** - Separate USSD from WhatsApp sessions  
- **`:gateway`** - Separate sessions per gateway
- **`[]`** - Global sessions (no boundaries)

Session identifier options:

- **`nil`** - Platform chooses default (`:request_id` for USSD, `:msisdn` for WhatsApp)
- **`:msisdn`** - Use phone number (durable sessions)
- **`:request_id`** - Use request ID (ephemeral sessions)
- **`hash_phone_numbers`** - Hash phone numbers for privacy (recommended)

## Middleware

### Custom Middleware

```ruby
class AuthenticationMiddleware
  def initialize(app)
    @app = app
  end

  def call(context)
    phone = context["request.msisdn"]
    
    unless user_exists?(phone)
      # Return appropriate response for unregistered user
      return [:prompt, "Please register first. Visit our website to sign up.", nil, nil]
    end
    
    @app.call(context)
  end

  private

  def user_exists?(phone)
    User.exists?(phone: phone)
  end
end

# Use custom middleware
processor = FlowChat::Ussd::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::CacheSessionStore
  config.use_middleware AuthenticationMiddleware
end
```

## Advanced Patterns

### Menu-Driven Navigation

```ruby
class MenuFlow < FlowChat::Flow
  def main_page
    choice = app.screen(:main_menu) do |prompt|
      prompt.select "Main Menu:", {
        "1" => "Account Services",
        "2" => "Transfer Services", 
        "3" => "Customer Support"
      }
    end

    case choice
    when "1"
      account_services
    when "2"
      transfer_services
    when "3"
      customer_support
    end
  end

  def account_services
    choice = app.screen(:account_menu) do |prompt|
      prompt.select "Account Services:", {
        "1" => "Check Balance",
        "2" => "Mini Statement",
        "0" => "Back to Main Menu"
      }
    end

    case choice
    when "1"
      check_balance
    when "2"
      mini_statement
    when "0"
      main_page  # Return to main menu
    end
  end
end
```

### Error Handling

```ruby
def transfer_money
  begin
    amount = app.screen(:amount) do |prompt|
      prompt.ask "Enter amount:",
        validate: ->(input) {
          return "Amount must be numeric" unless input.match?(/^\d+(\.\d{2})?$/)
          return "Minimum transfer is $1" unless input.to_f >= 1.0
          nil
        },
        transform: ->(input) { input.to_f }
    end

    recipient = app.screen(:recipient) do |prompt|
      prompt.ask "Enter recipient phone number:",
        validate: ->(input) {
          return "Invalid phone number" unless valid_phone?(input)
          nil
        }
    end

    process_transfer(amount, recipient)
    app.say "Transfer of $#{amount} to #{recipient} successful!"

  rescue TransferError => e
    app.say "Transfer failed: #{e.message}. Please try again."
    transfer_money  # Retry
  end
end
```

### Session Data Management

```ruby
class RegistrationFlow < FlowChat::Flow
  def main_page
    collect_personal_info
    collect_preferences
    confirm_and_save
  end

  private

  def collect_personal_info
    app.screen(:first_name) { |p| p.ask "First name:" }
    app.screen(:last_name) { |p| p.ask "Last name:" }
    app.screen(:email) { |p| p.ask "Email address:" }
  end

  def collect_preferences
    app.screen(:language) { |p| p.select "Language:", ["English", "French"] }
    app.screen(:notifications) { |p| p.yes? "Enable SMS notifications?" }
  end

  def confirm_and_save
    summary = build_summary_from_session
    confirmed = app.screen(:confirm) { |p| p.yes? "Save profile?\n\n#{summary}" }

    if confirmed
      save_user_profile
      app.say "Registration complete!"
    else
      app.say "Registration cancelled."
    end
  end

  def build_summary_from_session
    first_name = app.session.get(:first_name)
    last_name = app.session.get(:last_name)
    email = app.session.get(:email)
    language = app.session.get(:language)
    
    "Name: #{first_name} #{last_name}\nEmail: #{email}\nLanguage: #{language}"
  end
end
```

## Testing USSD Flows

Use the built-in simulator for testing USSD flows:

```ruby
# config/initializers/flowchat.rb
FlowChat::Config.simulator_secret = "your_secure_secret"
```

See [Testing Guide](testing.md) for comprehensive testing strategies and [examples/ussd_controller.rb](../examples/ussd_controller.rb) for complete implementation examples. 