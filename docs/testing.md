# Testing Guide

FlowChat provides comprehensive testing capabilities for both USSD and WhatsApp flows. This guide covers everything from unit testing individual flows to using the powerful built-in simulator for interactive testing.

## Testing Approaches

FlowChat supports multiple testing strategies depending on your needs:

| Approach | Best For | Setup Complexity | Real API Calls |
|----------|----------|------------------|----------------|
| **Unit Testing** | Individual flow logic | Low | No |
| **Simulator Mode** | Integration testing, development | Medium | No |
| **Skip Validation** | Staging environments | Medium | Yes |
| **Full Integration** | Production-like testing | High | Yes |

## Quick Start: Interactive Simulator

The fastest way to test your flows is with the built-in web simulator:

### 1. Configure Simulator

```ruby
# config/initializers/flowchat.rb
FlowChat::Config.simulator_secret = Rails.application.secret_key_base + "_simulator"
```

### 2. Create Simulator Controller

```ruby
# app/controllers/simulator_controller.rb
class SimulatorController < ApplicationController
  include FlowChat::Simulator::Controller

  def index
    flowchat_simulator
  end

  protected

  def configurations
    {
      ussd: {
        name: "USSD Integration",
        icon: "📱", 
        processor_type: "ussd",
        gateway: "nalo",
        endpoint: "/ussd",
        color: "#007bff"
      },
      whatsapp: {
        name: "WhatsApp Integration",
        icon: "💬",
        processor_type: "whatsapp", 
        gateway: "cloud_api",
        endpoint: "/whatsapp/webhook",
        color: "#25D366"
      }
    }
  end

  def default_config_key
    :whatsapp
  end

  def default_phone_number
    "+1234567890"
  end

  def default_contact_name
    "Test User"
  end
end
```

### 3. Add Route

```ruby
# config/routes.rb
Rails.application.routes.draw do
  get '/simulator' => 'simulator#index'
  # ... your other routes
end
```

### 4. Enable Simulator in Controllers

```ruby
# app/controllers/whatsapp_controller.rb
class WhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
  enable_simulator = Rails.env.development? # enabled in development by default
    processor = FlowChat::Whatsapp::Processor.new(self, enable_simulator:) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end
```

### 5. Test Your Flows

Visit [http://localhost:3000/simulator](http://localhost:3000/simulator) and start testing! 

**Simulator Features:**
- 📱 **Visual Interface** - Phone-like display showing actual conversation
- 🔄 **Platform Switching** - Toggle between USSD and WhatsApp modes  
- 📊 **Request Logging** - See HTTP requests and responses in real-time
- 🎯 **Interactive Testing** - Character counting, validation, session management
- 🛠️ **Developer Tools** - Reset sessions, view connection status

## Unit Testing

Test individual flows in isolation:

### Basic Flow Testing

```ruby
# test/flows/welcome_flow_test.rb
require 'test_helper'

class WelcomeFlowTest < ActiveSupport::TestCase
  def setup
    @context = FlowChat::Context.new
    @context.session = FlowChat::Session::CacheSessionStore.new
    @context.session.init_session("test_session")
  end

  test "welcome flow collects name and shows greeting" do
    # Simulate user entering name
    @context.input = "John Doe"
    app = FlowChat::Ussd::App.new(@context)
    
    # Expect flow to terminate with greeting
    error = assert_raises(FlowChat::Interrupt::Terminate) do
      flow = WelcomeFlow.new(app)
      flow.main_page
    end
    
    assert_includes error.prompt, "Hello, John Doe"
  end

  test "flow handles validation errors" do
    # Test with empty input
    @context.input = ""
    app = FlowChat::Ussd::App.new(@context)
    
    # Should prompt for input again
    error = assert_raises(FlowChat::Interrupt::Input) do
      flow = RegistrationFlow.new(app)
      flow.collect_email
    end
    
    assert_includes error.prompt, "Email is required"
  end
end
```

### Testing Complex Flows

```ruby
# test/flows/registration_flow_test.rb
class RegistrationFlowTest < ActiveSupport::TestCase
  test "complete registration flow" do
    context = FlowChat::Context.new
    context.session = FlowChat::Session::CacheSessionStore.new
    context.session.init_session("test_session")
    
    # Step 1: Enter email
    context.input = "john@example.com"
    app = FlowChat::Ussd::App.new(context)
    
    assert_raises(FlowChat::Interrupt::Input) do
      flow = RegistrationFlow.new(app)
      flow.main_page
    end
    
    # Verify email was stored
    assert_equal "john@example.com", context.session.get(:email)
    
    # Step 2: Enter age
    context.input = "25"
    
    assert_raises(FlowChat::Interrupt::Input) do
      flow = RegistrationFlow.new(app)
      flow.main_page  # Continue from where we left off
    end
    
    # Step 3: Confirm
    context.input = "yes"
    
    assert_raises(FlowChat::Interrupt::Terminate) do
      flow = RegistrationFlow.new(app)
      flow.main_page
    end
  end
end
```

## Integration Testing

### Environment Configuration

Set up different testing modes per environment:

```ruby
# config/initializers/flowchat.rb
case Rails.env
when 'development'
  # Use simulator for easy testing
  FlowChat::Config.whatsapp.message_handling_mode = :simulator
  FlowChat::Config.simulator_secret = Rails.application.secret_key_base + "_dev"
  
when 'test'
  # Use simulator for automated tests
  FlowChat::Config.whatsapp.message_handling_mode = :simulator
  FlowChat::Config.simulator_secret = "test_secret_key"
  
when 'staging'
  # Use inline mode with real WhatsApp API but skip validation for testing
  FlowChat::Config.whatsapp.message_handling_mode = :inline
  FlowChat::Config.simulator_secret = ENV['FLOWCHAT_SIMULATOR_SECRET']
  
when 'production'
  # Use background jobs with full security
  FlowChat::Config.whatsapp.message_handling_mode = :background
  FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
  # No simulator secret in production
end
```

### Simulator Mode Testing

Test webhook endpoints using simulator mode:

```ruby
# test/controllers/whatsapp_controller_test.rb
class WhatsappControllerTest < ActionDispatch::IntegrationTest
  test "processes whatsapp message in simulator mode" do
    webhook_payload = {
      entry: [{
        changes: [{
          value: {
            messages: [{
              from: "1234567890",
              text: { body: "Hello" },
              type: "text",
              id: "msg_123",
              timestamp: Time.now.to_i
            }]
          }
        }]
      }],
      simulator_mode: true  # Enable simulator mode
    }

    # Generate valid simulator cookie
    valid_cookie = generate_simulator_cookie
    
    post "/whatsapp/webhook",
      params: webhook_payload,
      cookies: { flowchat_simulator: valid_cookie }
    
    assert_response :success
    
    # In simulator mode, response contains message data
    response_data = JSON.parse(response.body)
    assert response_data.key?("text")
    assert_includes response_data["text"], "What's your name?"
  end

  test "multi-step flow maintains state" do
    valid_cookie = generate_simulator_cookie
    
    # Step 1: Start conversation
    post_simulator_message("start", valid_cookie)
    assert_response :success
    
    # Step 2: Enter name
    post_simulator_message("John", valid_cookie)
    assert_response :success
    
    response_data = JSON.parse(response.body)
    assert_includes response_data["text"], "Hello John"
  end

  private

  def generate_simulator_cookie(secret = "test_secret_key")
    timestamp = Time.now.to_i
    message = "simulator:#{timestamp}"
    signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, message)
    "#{timestamp}:#{signature}"
  end

  def post_simulator_message(text, cookie)
    webhook_payload = {
      entry: [{
        changes: [{
          value: {
            messages: [{
              from: "1234567890",
              text: { body: text },
              type: "text",
              id: "msg_#{rand(1000)}",
              timestamp: Time.now.to_i
            }]
          }
        }]
      }],
      simulator_mode: true
    }

    post "/whatsapp/webhook",
      params: webhook_payload,
      cookies: { flowchat_simulator: cookie }
  end
end
```

### Testing with Disabled Validation

For staging environments where you want to test real endpoints:

```ruby
test "webhook with disabled validation" do
  # Create config with validation disabled
  config = FlowChat::Whatsapp::Configuration.new(:test_config)
  config.access_token = "test_token"
  config.phone_number_id = "test_phone_id"
  config.verify_token = "test_verify"
  config.skip_signature_validation = true  # Disable validation for testing

  webhook_payload = {
    entry: [{
      changes: [{
        value: {
          messages: [{
            from: "1234567890",
            text: { body: "Hello" },
            type: "text"
          }]
        }
      }]
    }]
  }

  post "/whatsapp/webhook",
    params: webhook_payload.to_json,
    headers: { "Content-Type" => "application/json" }
  
  assert_response :success
end
```

## Advanced Testing Scenarios

### Testing Error Handling

```ruby
test "handles validation errors gracefully" do
  valid_cookie = generate_simulator_cookie
  
  # Send invalid email
  post_simulator_message("invalid-email", valid_cookie)
  
  response_data = JSON.parse(response.body)
  assert_includes response_data["text"], "Invalid email format"
  
  # Send valid email - should proceed
  post_simulator_message("john@example.com", valid_cookie)
  
  response_data = JSON.parse(response.body)
  refute_includes response_data["text"], "Invalid email"
end
```

### Testing Media Responses

```ruby
test "media responses in simulator mode" do
  valid_cookie = generate_simulator_cookie
  
  post_simulator_message("help", valid_cookie)
  
  response_data = JSON.parse(response.body)
  
  # Check media is included
  assert response_data.key?("media")
  assert_equal "image", response_data["media"]["type"]
  assert response_data["media"]["url"].present?
end
```

### Testing Session Persistence

```ruby
test "session data persists across requests" do
  valid_cookie = generate_simulator_cookie
  
  # First request - enter name
  post_simulator_message("John", valid_cookie)
  
  # Second request - session should remember name
  post_simulator_message("continue", valid_cookie)
  
  response_data = JSON.parse(response.body)
  assert_includes response_data["text"], "John"  # Name should be remembered
end
```

## Performance Testing

### Load Testing Background Jobs

```ruby
test "handles high message volume with background jobs" do
  # Switch to background mode for this test
  original_mode = FlowChat::Config.whatsapp.message_handling_mode
  FlowChat::Config.whatsapp.message_handling_mode = :background
  
  messages = 10.times.map do |i|
    create_whatsapp_message_payload("user#{i}")
  end
  
  assert_enqueued_jobs 10 do
    messages.each do |msg|
      post "/whatsapp/webhook", params: msg
    end
  end
ensure
  FlowChat::Config.whatsapp.message_handling_mode = original_mode
end
```

## Debugging Tests

### Enable Debug Logging

```ruby
# config/environments/test.rb
config.log_level = :debug

# In tests
Rails.logger.debug "Current session data: #{context.session.data}"
```

### Inspect Flow State

```ruby
test "debug flow execution" do
  context = FlowChat::Context.new
  context.session = FlowChat::Session::CacheSessionStore.new
  context.session.init_session("debug_session")
  
  # Add debugging
  context.input = "test@example.com"
  app = FlowChat::Ussd::App.new(context)
  
  flow = RegistrationFlow.new(app)
  
  # Inspect state before execution
  puts "Session before: #{context.session.data}"
  
  begin
    flow.main_page
  rescue FlowChat::Interrupt::Input => e
    puts "Flow interrupted with: #{e.prompt}"
    puts "Session after: #{context.session.data}"
  end
end
```
