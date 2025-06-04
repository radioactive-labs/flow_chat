# FlowChat

FlowChat is a Rails framework designed for building sophisticated conversational workflows, particularly for USSD (Unstructured Supplementary Service Data) systems. It provides an intuitive Ruby DSL for creating multi-step, menu-driven conversations with automatic session management, input validation, and flow control.

**Key Features:**
- 🎯 **Declarative Flow Definition** - Define conversation flows as Ruby classes
- 🔄 **Automatic Session Management** - Persistent state across requests  
- ✅ **Input Validation & Transformation** - Built-in validation and data conversion
- 🌊 **Middleware Architecture** - Flexible request processing pipeline
- 📱 **USSD Gateway Support** - Currently supports Nalo and Nsano gateways
- 🧪 **Built-in Testing Tools** - USSD simulator for local development

## Architecture Overview

FlowChat uses a **request-per-interaction** model where each user input creates a new request. The framework maintains conversation state through session storage while processing each interaction through a middleware pipeline.

```
User Input → Gateway → Session → Pagination → Custom → Executor → Flow → Response
                ↓
         Session Storage
```

**Middleware Pipeline:**
- **Gateway**: USSD provider communication (Nalo/Nsano)
- **Session**: Load/save conversation state  
- **Pagination**: Split long responses into pages
- **Custom**: Your application middleware (logging, auth, etc.)
- **Executor**: Execute flow methods and handle interrupts

## Installation

Add FlowChat to your Rails application's Gemfile:

```ruby
gem 'flow_chat'
```

Then execute:

```bash
bundle install
```

## Quick Start

### 1. Create Your First Flow

Create a flow class in `app/flow_chat/welcome_flow.rb`:

```ruby
class WelcomeFlow < FlowChat::Flow
  def main_page
    name = app.screen(:name) do |prompt|
      prompt.ask "Welcome! What's your name?",
        transform: ->(input) { input.strip.titleize }
    end

    app.say "Hello, #{name}! Welcome to FlowChat."
  end
end
```

### 2. Set Up the Controller

Create a controller to handle USSD requests:

```ruby
class UssdController < ApplicationController
  skip_forgery_protection

  def process_request
    processor = FlowChat::Ussd::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      config.use_session_store FlowChat::Session::RailsSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end
```

### 3. Configure Routes

Add the route to `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  post 'ussd' => 'ussd#process_request'
end
```

## Core Concepts

### Flows and Screens

**Flows** are Ruby classes that define conversation logic. **Screens** represent individual interaction points where you collect user input.

```ruby
class RegistrationFlow < FlowChat::Flow
  def main_page
    # Each screen captures one piece of user input
    phone = app.screen(:phone) do |prompt|
      prompt.ask "Enter your phone number:",
        validate: ->(input) { "Invalid phone number" unless valid_phone?(input) }
    end

    age = app.screen(:age) do |prompt|
      prompt.ask "Enter your age:",
        convert: ->(input) { input.to_i },
        validate: ->(input) { "Must be 18 or older" unless input >= 18 }
    end

    # Process the collected data
    create_user(phone: phone, age: age)
    app.say "Registration complete!"
  end

  private

  def valid_phone?(phone)
    phone.match?(/\A\+?[\d\s\-\(\)]+\z/)
  end

  def create_user(phone:, age:)
    # Your user creation logic here
  end
end
```

### Input Validation and Transformation

FlowChat provides powerful input processing capabilities:

```ruby
app.screen(:email) do |prompt|
  prompt.ask "Enter your email:",
    # Transform input before validation
    transform: ->(input) { input.strip.downcase },
    
    # Validate the input
    validate: ->(input) { 
      "Invalid email format" unless input.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
    },
    
    # Convert to final format
    convert: ->(input) { input }
end
```

### Menu Selection

Create selection menus with automatic validation:

```ruby
# Array-based choices
language = app.screen(:language) do |prompt|
  prompt.select "Choose your language:", ["English", "French", "Spanish"]
end

# Hash-based choices (keys are returned values)
plan = app.screen(:plan) do |prompt|
  prompt.select "Choose a plan:", {
    "basic" => "Basic Plan ($10/month)",
    "premium" => "Premium Plan ($25/month)",
    "enterprise" => "Enterprise Plan ($100/month)"
  }
end
```

### Yes/No Prompts

Simplified boolean input collection:

```ruby
confirmed = app.screen(:confirmation) do |prompt|
  prompt.yes? "Do you want to proceed with the payment?"
end

if confirmed
  process_payment
  app.say "Payment processed successfully!"
else
  app.say "Payment cancelled."
end
```

## Advanced Features

### Session Management and Flow State

FlowChat automatically manages session state across requests. Each screen's result is cached, so users can navigate back and forth without losing data:

```ruby
class OrderFlow < FlowChat::Flow
  def main_page
    # These values persist across requests
    product = app.screen(:product) { |p| p.select "Choose product:", products }
    quantity = app.screen(:quantity) { |p| p.ask "Quantity:", convert: :to_i }
    
    # Show summary
    total = calculate_total(product, quantity)
    confirmed = app.screen(:confirm) do |prompt|
      prompt.yes? "Order #{quantity}x #{product} for $#{total}. Confirm?"
    end

    if confirmed
      process_order(product, quantity)
      app.say "Order placed successfully!"
    else
      app.say "Order cancelled."
    end
  end
end
```

### Error Handling

Handle validation errors gracefully:

```ruby
app.screen(:credit_card) do |prompt|
  prompt.ask "Enter credit card number:",
    validate: ->(input) {
      return "Card number must be 16 digits" unless input.length == 16
      return "Invalid card number" unless luhn_valid?(input)
      nil # Return nil for valid input
    }
end
```

### Middleware Configuration

FlowChat uses a **middleware architecture** to process USSD requests through a configurable pipeline. Each request flows through multiple middleware layers in a specific order.

#### Default Middleware Stack

When you run a flow, FlowChat automatically builds this middleware stack:

```
User Input → Gateway → Session → Pagination → Custom Middleware → Executor → Flow
```

1. **Gateway Middleware** - Handles USSD provider communication (Nalo/Nsano)
2. **Session Middleware** - Manages session storage and retrieval
3. **Pagination Middleware** - Automatically splits long responses across pages
4. **Custom Middleware** - Your application-specific middleware (optional)
5. **Executor Middleware** - Executes the actual flow logic

#### Basic Configuration

```ruby
processor = FlowChat::Ussd::Processor.new(self) do |config|
  # Gateway configuration (required)
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  
  # Session storage (required)
  config.use_session_store FlowChat::Session::RailsSessionStore
  
  # Add custom middleware (optional)
  config.use_middleware MyLoggingMiddleware
  
  # Enable resumable sessions (optional)
  config.use_resumable_sessions
end
```

#### Runtime Middleware Modification

You can modify the middleware stack at runtime for advanced use cases:

```ruby
processor.run(MyFlow, :main_page) do |stack|
  # Add authentication middleware
  stack.use AuthenticationMiddleware
  
  # Insert rate limiting before execution
  stack.insert_before FlowChat::Ussd::Middleware::Executor, RateLimitMiddleware
  
  # Add logging after gateway
  stack.insert_after gateway, RequestLoggingMiddleware
end
```

#### Built-in Middleware

**Pagination Middleware** automatically handles responses longer than 182 characters (configurable):

```ruby
# Configure pagination behavior
FlowChat::Config.ussd.pagination_page_size = 140        # Default: 140 characters
FlowChat::Config.ussd.pagination_next_option = "#"      # Default: "#"
FlowChat::Config.ussd.pagination_next_text = "More"     # Default: "More"
FlowChat::Config.ussd.pagination_back_option = "0"      # Default: "0"
FlowChat::Config.ussd.pagination_back_text = "Back"     # Default: "Back"
```

**Resumable Sessions** allow users to continue interrupted conversations:

```ruby
processor = FlowChat::Ussd::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::RailsSessionStore
  config.use_resumable_sessions  # Enable resumable sessions
end
```

#### Creating Custom Middleware

```ruby
class LoggingMiddleware
  def initialize(app)
    @app = app
  end

  def call(context)
    Rails.logger.info "Processing USSD request: #{context.input}"
    
    # Call the next middleware in the stack
    result = @app.call(context)
    
    Rails.logger.info "Response: #{result[1]}"
    result
  end
end

# Use your custom middleware
processor = FlowChat::Ussd::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::RailsSessionStore
  config.use_middleware LoggingMiddleware
end
```

### Multiple Gateways

FlowChat supports multiple USSD gateways:

```ruby
# Nalo Solutions Gateway
config.use_gateway FlowChat::Ussd::Gateway::Nalo

# Nsano Gateway  
config.use_gateway FlowChat::Ussd::Gateway::Nsano
```

## Testing

### Unit Testing Flows

Test your flows in isolation using the provided test helpers:

```ruby
require 'test_helper'

class WelcomeFlowTest < Minitest::Test
  def setup
    @context = FlowChat::Context.new
    @context.session = create_test_session_store
  end

  def test_welcome_flow_with_name
    @context.input = "John Doe"
    app = FlowChat::Ussd::App.new(@context)
    
    error = assert_raises(FlowChat::Interrupt::Terminate) do
      flow = WelcomeFlow.new(app)
      flow.main_page
    end
    
    assert_equal "Hello, John Doe! Welcome to FlowChat.", error.prompt
  end

  def test_welcome_flow_without_input
    @context.input = nil
    app = FlowChat::Ussd::App.new(@context)
    
    error = assert_raises(FlowChat::Interrupt::Prompt) do
      flow = WelcomeFlow.new(app)
      flow.main_page
    end
    
    assert_equal "Welcome! What's your name?", error.prompt
  end
end
```

### Integration Testing

Test complete user journeys:

```ruby
class RegistrationFlowIntegrationTest < Minitest::Test
  def test_complete_registration_flow
    controller = mock_controller
    processor = FlowChat::Ussd::Processor.new(controller) do |config|
      config.use_gateway MockGateway
      config.use_session_store FlowChat::Session::RailsSessionStore
    end

    # Simulate the complete flow
    # First request - ask for phone
    # Second request - provide phone, ask for age  
    # Third request - provide age, complete registration
  end
end
```

### Testing Middleware

Test your custom middleware in isolation:

```ruby
class LoggingMiddlewareTest < Minitest::Test
  def test_logs_request_and_response
    # Mock the next app in the chain
    app = lambda { |context| [:prompt, "Test response", []] }
    middleware = LoggingMiddleware.new(app)
    
    context = FlowChat::Context.new
    context.input = "test input"
    
    # Capture log output
    log_output = StringIO.new
    Rails.stub(:logger, Logger.new(log_output)) do
      type, prompt, choices = middleware.call(context)
      
      assert_equal :prompt, type
      assert_equal "Test response", prompt
      assert_includes log_output.string, "Processing USSD request: test input"
      assert_includes log_output.string, "Response: Test response"
    end
  end
end
```

### Testing Middleware Stack Modification

Test runtime middleware modifications:

```ruby
class ProcessorMiddlewareTest < Minitest::Test
  def test_custom_middleware_insertion
    controller = mock_controller
    processor = FlowChat::Ussd::Processor.new(controller) do |config|
      config.use_gateway MockGateway
      config.use_session_store FlowChat::Session::RailsSessionStore
    end
    
    custom_middleware_called = false
    custom_middleware = Class.new do
      define_method(:initialize) { |app| @app = app }
      define_method(:call) do |context|
        custom_middleware_called = true
        @app.call(context)
      end
    end
    
    processor.run(TestFlow, :main_page) do |stack|
      stack.use custom_middleware
      stack.insert_before FlowChat::Ussd::Middleware::Executor, custom_middleware
    end
    
    assert custom_middleware_called, "Custom middleware should have been executed"
  end
end
```

### USSD Simulator

Use the built-in simulator for interactive testing:

```ruby
class UssdSimulatorController < ApplicationController
  include FlowChat::Ussd::Simulator::Controller

  protected

  def default_endpoint
    '/ussd'
  end

  def default_provider
    :nalo
  end
end
```

Add to routes and visit `http://localhost:3000/ussd_simulator`.

## Best Practices

### 1. Keep Flows Focused

Create separate flows for different user journeys:

```ruby
# Good: Focused flows
class LoginFlow < FlowChat::Flow
  # Handle user authentication
end

class RegistrationFlow < FlowChat::Flow
  # Handle user registration  
end

class AccountFlow < FlowChat::Flow
  # Handle account management
end
```

### 2. Use Descriptive Screen Names

Screen names should clearly indicate their purpose:

```ruby
# Good
app.screen(:customer_phone_number) { |p| p.ask "Phone:" }
app.screen(:payment_confirmation) { |p| p.yes? "Confirm payment?" }

# Avoid
app.screen(:input1) { |p| p.ask "Phone:" }
app.screen(:confirm) { |p| p.yes? "Confirm payment?" }
```

### 3. Validate Early and Often

Always validate user input to provide clear feedback:

```ruby
app.screen(:amount) do |prompt|
  prompt.ask "Enter amount:",
    convert: ->(input) { input.to_f },
    validate: ->(amount) {
      return "Amount must be positive" if amount <= 0
      return "Maximum amount is $1000" if amount > 1000
      nil
    }
end
```

### 4. Handle Edge Cases

Consider error scenarios and provide helpful messages:

```ruby
def main_page
  begin
    process_user_request
  rescue PaymentError => e
    app.say "Payment failed: #{e.message}. Please try again."
  rescue SystemError
    app.say "System temporarily unavailable. Please try again later."
  end
end
```

## Configuration

### Session Storage Options

Configure different session storage backends:

```ruby
# Rails session (default)
config.use_session_store FlowChat::Session::RailsSessionStore

# Custom session store
class MySessionStore
  def initialize(context)
    @context = context
  end

  def get(key)
    # Your storage logic
  end

  def set(key, value)
    # Your storage logic
  end
end

config.use_session_store MySessionStore
```

## Development

### Running Tests

FlowChat uses Minitest for testing:

```bash
# Run all tests
bundle exec rake test

# Run specific test file
bundle exec rake test TEST=test/unit/flow_test.rb

# Run specific test
bundle exec rake test TESTOPTS="--name=test_flow_initialization"
```

### Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Add tests for your changes
4. Ensure all tests pass (`bundle exec rake test`)
5. Commit your changes (`git commit -am 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Roadmap

- 📱 **WhatsApp Integration** - Support for WhatsApp Business API
- 💬 **Telegram Bot Support** - Native Telegram bot integration  
- 🔄 **Sub-flows** - Reusable conversation components
- 📊 **Analytics Integration** - Built-in conversation analytics
- 🌐 **Multi-language Support** - Internationalization features
- ⚡ **Performance Optimizations** - Improved middleware performance

## License

FlowChat is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Support

- 📖 **Documentation**: [GitHub Repository](https://github.com/radioactive-labs/flow_chat)
- 🐛 **Bug Reports**: [GitHub Issues](https://github.com/radioactive-labs/flow_chat/issues)
- 💬 **Community**: Join our discussions for help and feature requests
