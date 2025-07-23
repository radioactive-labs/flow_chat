# Getting Started with FlowChat

This guide will walk you through setting up FlowChat and building your first conversational application that works across multiple platforms.

## Prerequisites

- Ruby 2.3+ (Ruby 3.0+ recommended)
- Rails 6.0+ (Rails 7.0+ recommended)
- Basic understanding of Rails controllers and routing

## Installation

Add FlowChat to your Rails application:

```ruby
# Gemfile
gem 'flow_chat'
```

```bash
bundle install
```

## Quick Start: Your First Multi-Platform App

Let's build a simple survey application that works across USSD, WhatsApp, and HTTP APIs.

### 1. Create the Flow

Create a new file `app/flow_chat/survey_flow.rb`:

```ruby
class SurveyFlow < FlowChat::Flow
  def start
    # Welcome message that works on all platforms
    name = app.screen(:name) do |prompt|
      prompt.ask "Welcome to our survey! What's your name?",
        validate: ->(input) {
          return "Name must be at least 2 characters" if input.length < 2
          nil
        },
        transform: ->(input) { input.strip.titleize }
    end

    # Rating question with platform-appropriate choices
    rating = app.screen(:rating) do |prompt|
      prompt.select "Hi #{name}! Rate our service:", {
        "5" => "⭐⭐⭐⭐⭐ Excellent",
        "4" => "⭐⭐⭐⭐ Good", 
        "3" => "⭐⭐⭐ Average",
        "2" => "⭐⭐ Poor",
        "1" => "⭐ Very Poor"
      }
    end

    # Feedback collection
    feedback = app.screen(:feedback) do |prompt|
      prompt.ask "Any additional feedback?",
        validate: ->(input) {
          return "Feedback too short" if input.length < 5
          nil
        }
    end

    # Save the survey (your business logic)
    save_survey(name, rating, feedback, app.msisdn)

    # Thank you message
    app.say "Thank you #{name}! Your feedback (#{rating}⭐) has been recorded."
  end

  private

  def save_survey(name, rating, feedback, phone)
    # Your database logic here
    Rails.logger.info "Survey: #{name} (#{phone}) rated #{rating}/5: #{feedback}"
    
    # Example: Save to database
    # Survey.create!(
    #   name: name,
    #   rating: rating.to_i,
    #   feedback: feedback,
    #   phone: phone,
    #   platform: app.platform
    # )
  end
end
```

### 2. Create Controllers for Each Platform

#### USSD Controller

```ruby
# app/controllers/ussd_controller.rb
class UssdController < ApplicationController
  skip_forgery_protection
  
  def nalo_webhook
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      config.use_session_store FlowChat::Session::RailsSessionStore
      
      # Optional: Configure USSD-specific settings
      config.use_session_config(boundaries: [:flow, :platform])
    end

    processor.run SurveyFlow, :start
  end
end
```

#### WhatsApp Controller

```ruby
# app/controllers/whatsapp_controller.rb
class WhatsappController < ApplicationController
  skip_forgery_protection
  
  def webhook
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run SurveyFlow, :start
  rescue => e
    Rails.logger.error "WhatsApp error: #{e.message}"
    head :internal_server_error
  end
end
```

#### HTTP API Controller

```ruby
# app/controllers/api/chat_controller.rb
class Api::ChatController < ApplicationController
  before_action :authenticate_api_user # Your auth logic
  
  def message
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Http::Gateway::Simple
      config.use_session_store FlowChat::Session::RailsSessionStore
      
      # Session isolation per API user
      config.use_session_config(identifier: :user_id)
    end

    processor.run SurveyFlow, :start
    # Automatically returns JSON response
  end
end
```

### 3. Add Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # USSD routes
  post '/ussd/nalo', to: 'ussd#nalo_webhook'
  
  # WhatsApp routes  
  post '/whatsapp/webhook', to: 'whatsapp#webhook'
  get '/whatsapp/webhook', to: 'whatsapp#verify' # For webhook verification
  
  # API routes
  namespace :api do
    post '/chat/message', to: 'chat#message'
  end
end
```

### 4. Configuration

#### Environment Variables

Add these to your `.env` file:

```bash
# WhatsApp Configuration
WHATSAPP_ACCESS_TOKEN=your_access_token
WHATSAPP_PHONE_NUMBER_ID=your_phone_number_id
WHATSAPP_VERIFY_TOKEN=your_verify_token
WHATSAPP_APP_SECRET=your_app_secret
```

#### FlowChat Configuration

Create `config/initializers/flow_chat.rb`:

```ruby
FlowChat::Config.logger = Rails.logger
FlowChat::Config.cache = Rails.cache

# USSD Configuration
FlowChat::Config.ussd.pagination_page_size = 160  # Adjust for your network
FlowChat::Config.ussd.pagination_next_option = "#"
FlowChat::Config.ussd.pagination_back_option = "0"

# WhatsApp Configuration
FlowChat::Config.whatsapp.message_handling_mode = :inline  # or :background
```

### 5. Test Your Application

#### Using the Built-in Simulator

Create a simple test in `rails console`:

```ruby
# Start a simulator session
simulator = FlowChat::Simulator.new(SurveyFlow, :start)

# Simulate the conversation
simulator.start
# => "Welcome to our survey! What's your name?"

simulator.send_message("John Doe")
# => "Hi John Doe! Rate our service:"

simulator.select_option("5")
# => "Any additional feedback?"

simulator.send_message("Great service, very helpful!")
# => "Thank you John Doe! Your feedback (5⭐) has been recorded."
```

#### Testing HTTP API

```bash
# Test the HTTP endpoint
curl -X POST http://localhost:3000/api/chat/message \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your_api_token" \
  -d '{
    "user_id": "user123",
    "input": "Hello"
  }'
```

#### Testing USSD (using simulator)

Visit your Rails app with the simulator enabled:

```ruby
# In development, add this to your controller
processor = FlowChat::Processor.new(self, enable_simulator: true) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  # ... other config
end
```

## Key Concepts

### 1. Screen-Based Navigation

FlowChat uses a **screen-based** approach where each `app.screen(:key)` represents a step in your conversation:

- **Automatic State Management**: Each screen's result is automatically cached
- **Navigation Stack**: FlowChat tracks where users are in the flow  
- **Resume Capability**: Users can return to where they left off

### 2. Platform Abstraction

The same flow code works across all platforms because:

- **Unified Prompts**: `prompt.ask()` and `prompt.select()` adapt to each platform
- **Context Normalization**: All platforms provide consistent context (phone number, input, etc.)
- **Flexible Rendering**: Emojis show on WhatsApp, get stripped for USSD

### 3. Pluggable Gateways

Each platform can have multiple gateway implementations:

```ruby
# USSD with different providers
config.use_gateway FlowChat::Ussd::Gateway::Nalo
# config.use_gateway FlowChat::Ussd::Gateway::Africaist
# config.use_gateway YourCompany::Ussd::Gateway::CustomProvider

# WhatsApp with different APIs
config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
# config.use_gateway FlowChat::Whatsapp::Gateway::OnPremise
# config.use_gateway YourCompany::Whatsapp::Gateway::Twilio
```

### 4. Session Management

FlowChat provides flexible session configuration:

```ruby
# Ephemeral sessions (restart on each request)
config.use_session_config(identifier: :request_id)

# Durable sessions (persist across timeouts using phone number)
config.use_durable_sessions

# Cross-platform sessions (same user, different platforms)
config.use_cross_platform_sessions

# Multi-tenant isolation
config.use_url_isolation
```

## Next Steps

Now that you have a basic multi-platform application running:

1. **Explore Platform Features**: Learn platform-specific capabilities
   - [USSD Development](platforms/ussd.md) - Pagination, choice mapping
   - [WhatsApp Development](platforms/whatsapp.md) - Rich media, templates
   - [HTTP Development](platforms/http.md) - API integration patterns

2. **Advanced Topics**:
   - [Session Management](../session-management.md) - Deep dive into session boundaries
   - [Middleware Development](../middleware.md) - Custom processing logic
   - [Gateway Development](../gateway-development.md) - Build your own platform support

3. **Production Deployment**:
   - [Configuration](../configuration.md) - Production-ready settings
   - [Background Jobs](../background-jobs.md) - Async processing for WhatsApp
   - [Testing](../testing.md) - Comprehensive testing strategies

## Common Patterns

### Validation and Transformation

```ruby
app.screen(:phone) do |prompt|
  prompt.ask "Enter your phone number:",
    validate: ->(input) {
      return "Invalid phone format" unless input.match?(/^\+?[\d\s-()]+$/)
      parsed = Phonelib.parse(input)
      return "Invalid phone number" unless parsed.valid?
      nil
    },
    transform: ->(input) { Phonelib.parse(input).e164 }
end
```

### Conditional Flow Logic

```ruby
def main_menu
  user_type = determine_user_type(app.msisdn)
  
  if user_type == :premium
    premium_menu
  else
    basic_menu
  end
end
```

### Error Handling

```ruby
def payment_flow
  begin
    amount = app.screen(:amount) { |p| p.ask "Enter amount:" }
    process_payment(amount)
    app.say "Payment successful!"
  rescue PaymentError => e
    app.say "Payment failed: #{e.message}"
  end
end
```

## Troubleshooting

### Common Issues

1. **Session Not Persisting**
   - Check your session store configuration
   - Verify session boundaries match your use case

2. **Gateway Errors**
   - Ensure environment variables are set correctly
   - Check gateway-specific configuration requirements

3. **Platform Differences**
   - Test flows on each platform's simulator
   - Be aware of character limits (USSD) vs rich features (WhatsApp)

### Debug Mode

Enable comprehensive logging:

```ruby
# config/initializers/flow_chat.rb
FlowChat::Config.logger.level = Logger::DEBUG

# In your flow
Rails.logger.debug "Current screen: #{app.navigation_stack.last}"
Rails.logger.debug "User input: #{app.input.inspect}"
```

Ready to build more sophisticated flows? Continue with the [Architecture Overview](architecture.md) to understand FlowChat's design principles. 