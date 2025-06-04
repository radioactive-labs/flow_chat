# FlowChat

FlowChat is a Rails framework designed for building sophisticated conversational workflows for both USSD (Unstructured Supplementary Service Data) systems and WhatsApp messaging. It provides an intuitive Ruby DSL for creating multi-step, menu-driven conversations with automatic session management, input validation, and flow control.

**Key Features:**
- 🎯 **Declarative Flow Definition** - Define conversation flows as Ruby classes
- 🔄 **Automatic Session Management** - Persistent state across requests  
- ✅ **Input Validation & Transformation** - Built-in validation and data conversion
- 🌊 **Middleware Architecture** - Flexible request processing pipeline
- 📱 **USSD Gateway Support** - Currently supports Nalo gateways
- 💬 **WhatsApp Integration** - Full WhatsApp Cloud API support with multiple processing modes
- 🔧 **Reusable WhatsApp Client** - Standalone client for out-of-band messaging
- 🧪 **Built-in Testing Tools** - Unified simulator for both USSD and WhatsApp testing

## Architecture Overview

FlowChat uses a **request-per-interaction** model where each user input creates a new request. The framework maintains conversation state through session storage while processing each interaction through a middleware pipeline.

```
User Input → Gateway → Session → Pagination → Custom → Executor → Flow → Response
                ↓
         Session Storage
```

**Middleware Pipeline:**
- **Gateway**: Communication with providers (USSD: Nalo, WhatsApp: Cloud API)
- **Session**: Load/save conversation state  
- **Pagination**: Split long responses into pages (USSD only)
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

FlowChat supports both USSD and WhatsApp. Choose the platform that fits your needs:

### USSD Setup

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

### 2. Set Up the USSD Controller

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

💡 **Tip**: See [examples/ussd_controller.rb](examples/ussd_controller.rb) for a complete USSD controller example with payment flows, customer support, and custom middleware.

### WhatsApp Setup

### 1. Configure WhatsApp Credentials

FlowChat supports two ways to configure WhatsApp credentials:

**Option A: Using Rails Credentials**

Add your WhatsApp credentials to Rails credentials:

```bash
rails credentials:edit
```

```yaml
whatsapp:
  access_token: "your_access_token"
  phone_number_id: "your_phone_number_id"
  verify_token: "your_verify_token"
  app_id: "your_app_id"
  app_secret: "your_app_secret"
  business_account_id: "your_business_account_id"
```

**Option B: Using Environment Variables**

Alternatively, you can use environment variables:

```bash
# Add to your .env file or environment
export WHATSAPP_ACCESS_TOKEN="your_access_token"
export WHATSAPP_PHONE_NUMBER_ID="your_phone_number_id" 
export WHATSAPP_VERIFY_TOKEN="your_verify_token"
export WHATSAPP_APP_ID="your_app_id"
export WHATSAPP_APP_SECRET="your_app_secret"
export WHATSAPP_BUSINESS_ACCOUNT_ID="your_business_account_id"
```

FlowChat will automatically use Rails credentials first, falling back to environment variables if credentials are not available.

**Option C: Per-Setup Configuration**

For multi-tenant applications or when you need different WhatsApp accounts per endpoint:

```ruby
# Create custom configuration
custom_config = FlowChat::Whatsapp::Configuration.new
custom_config.access_token = "your_specific_access_token"
custom_config.phone_number_id = "your_specific_phone_number_id"
custom_config.verify_token = "your_specific_verify_token"
custom_config.app_id = "your_specific_app_id"
custom_config.app_secret = "your_specific_app_secret"
custom_config.business_account_id = "your_specific_business_account_id"

# Use in processor
processor = FlowChat::Whatsapp::Processor.new(self) do |config|
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, custom_config
  config.use_session_store FlowChat::Session::CacheSessionStore
end
```

💡 **Tip**: See [examples/multi_tenant_whatsapp_controller.rb](examples/multi_tenant_whatsapp_controller.rb) for comprehensive multi-tenant and per-setup configuration examples.

### 2. Choose Message Handling Mode

FlowChat offers three WhatsApp message handling modes. Configure them in an initializer:

**Create an initializer** `config/initializers/flowchat.rb`:

```ruby
# config/initializers/flowchat.rb

# Configure WhatsApp message handling mode
FlowChat::Config.whatsapp.message_handling_mode = :inline  # or :background, :simulator
FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
```

**Inline Mode (Default)** - Process messages synchronously:
```ruby
# config/initializers/flowchat.rb
FlowChat::Config.whatsapp.message_handling_mode = :inline

# app/controllers/whatsapp_controller.rb
class WhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Whatsapp::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end
```

**Background Mode** - Process flows synchronously, send responses asynchronously:
```ruby
# config/initializers/flowchat.rb
FlowChat::Config.whatsapp.message_handling_mode = :background
FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'

# app/controllers/whatsapp_controller.rb
class WhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Whatsapp::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end
```

**Simulator Mode** - Return response data instead of sending via WhatsApp API:
```ruby
# config/initializers/flowchat.rb
FlowChat::Config.whatsapp.message_handling_mode = :simulator

# app/controllers/whatsapp_controller.rb
class WhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Whatsapp::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end
```


### 3. Add WhatsApp Route

```ruby
Rails.application.routes.draw do
  match '/whatsapp/webhook', to: 'whatsapp#webhook', via: [:get, :post]
end
```

### 4. Enhanced Features for WhatsApp

The same flow works for both USSD and WhatsApp, but WhatsApp provides additional data and better interactive features:

```ruby
class WelcomeFlow < FlowChat::Flow
  def main_page
    # Access WhatsApp-specific data
    Rails.logger.info "Contact: #{app.contact_name}, Phone: #{app.phone_number}"
    Rails.logger.info "Message ID: #{app.message_id}, Timestamp: #{app.timestamp}"
    
    # Handle location sharing
    if app.location
      app.say "Thanks for sharing your location! We see you're at #{app.location['latitude']}, #{app.location['longitude']}"
      return
    end
    
    # Handle media messages  
    if app.media
      app.say "Thanks for the #{app.media['type']} file! We received: #{app.media['id']}"
      return
    end

    name = app.screen(:name) do |prompt|
      prompt.ask "Hello! Welcome to our WhatsApp service. What's your name?",
        transform: ->(input) { input.strip.titleize }
    end

    # WhatsApp supports interactive buttons and lists via prompt.select
    choice = app.screen(:main_menu) do |prompt|
      prompt.select "Hi #{name}! How can I help you?", {
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
        "services" => "💼 Our Services"
      }
    end

    case info_choice
    when "hours"
      app.say "We're open Monday-Friday 9AM-6PM, Saturday 10AM-4PM. Closed Sundays."
    when "location"
      app.say "📍 Visit us at 123 Main Street, Downtown. We're next to the coffee shop!"
    when "services"
      app.say "💼 We offer: Web Development, Mobile Apps, Cloud Services, and IT Consulting."
    end
  end

  def contact_support
    support_choice = app.screen(:support_menu) do |prompt|
      prompt.select "How would you like to contact support?", {
        "call" => "📞 Call Us",
        "email" => "📧 Email Us",
        "chat" => "💬 Continue Here"
      }
    end

    case support_choice
    when "call"
      app.say "📞 Call us at: +1-555-HELP (4357)\nAvailable Mon-Fri 9AM-5PM"
    when "email"  
      app.say "📧 Email us at: support@company.com\nWe typically respond within 24 hours"
    when "chat"
      app.say "💬 Great! Please describe your issue and we'll help you right away."
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

    # Use WhatsApp-specific data for logging
    Rails.logger.info "Feedback from #{app.contact_name} (#{app.phone_number}): #{rating} stars - #{feedback}"

    app.say "Thank you for your feedback! We really appreciate it. 🙏"
  end
end
```

For detailed WhatsApp setup instructions, see [WhatsApp Integration Guide](docs/whatsapp_setup.md).

## 🔧 Reusable WhatsApp Client

FlowChat provides a standalone WhatsApp client for out-of-band messaging:

```ruby
# Initialize client
config = FlowChat::Whatsapp::Configuration.from_credentials
client = FlowChat::Whatsapp::Client.new(config)

# Send text message
client.send_text("+1234567890", "Hello, World!")

# Send interactive buttons
client.send_buttons(
  "+1234567890",
  "Choose an option:",
  [
    { id: 'option1', title: 'Option 1' },
    { id: 'option2', title: 'Option 2' }
  ]
)

# Send interactive list
client.send_list(
  "+1234567890",
  "Select from menu:",
  [
    {
      title: "Services",
      rows: [
        { id: 'service1', title: 'Service 1', description: 'Description 1' },
        { id: 'service2', title: 'Service 2', description: 'Description 2' }
      ]
    }
  ]
)

# Handle media
media_url = client.get_media_url("media_id_123")
media_content = client.download_media("media_id_123")
```

### Out-of-Band Messaging Service Example

```ruby
class NotificationService
  def initialize
    @config = FlowChat::Whatsapp::Configuration.from_credentials
    @client = FlowChat::Whatsapp::Client.new(@config)
  end

  def send_order_confirmation(phone_number, order_id, items, total)
    item_list = items.map { |item| "• #{item[:name]} x#{item[:quantity]}" }.join("\n")
    
    @client.send_buttons(
      phone_number,
      "✅ Order Confirmed!\n\nOrder ##{order_id}\n\n#{item_list}\n\nTotal: $#{total}",
      [
        { id: 'track_order', title: '📦 Track Order' },
        { id: 'contact_support', title: '💬 Contact Support' }
      ]
    )
  end

  def send_appointment_reminder(phone_number, appointment)
    @client.send_buttons(
      phone_number,
      "🏥 Appointment Reminder\n\n#{appointment[:service]} with #{appointment[:provider]}\n📅 #{appointment[:date]}\n🕐 #{appointment[:time]}",
      [
        { id: 'confirm', title: '✅ Confirm' },
        { id: 'reschedule', title: '📅 Reschedule' },
        { id: 'cancel', title: '❌ Cancel' }
      ]
    )
  end
end
```


## Cross-Platform Compatibility

FlowChat provides a unified API that works across both USSD and WhatsApp platforms, with graceful degradation for platform-specific features:

### Shared Features (Both USSD & WhatsApp)
- ✅ `app.screen()` - Interactive screens with prompts
- ✅ `app.say()` - Send messages to users  
- ✅ `prompt.ask()` - Text input collection
- ✅ `prompt.select()` - Menu selection (renders as numbered list in USSD, interactive buttons/lists in WhatsApp)
- ✅ `prompt.yes?()` - Yes/no questions
- ✅ `app.phone_number` - User's phone number
- ✅ `app.message_id` - Unique message identifier  
- ✅ `app.timestamp` - Message timestamp

### WhatsApp-Only Features
- ✅ `app.contact_name` - WhatsApp contact name (returns `nil` in USSD)
- ✅ `app.location` - Location sharing data (returns `nil` in USSD)  
- ✅ `app.media` - Media file attachments (returns `nil` in USSD)
- ✅ Rich interactive elements (buttons, lists) automatically generated from `prompt.select()`

This design allows you to write flows once and deploy them on both platforms, with WhatsApp users getting enhanced interactive features automatically.

## 📱 Media Support

FlowChat supports rich media attachments for enhanced conversational experiences. Media can be attached to `ask()` and `say()` prompts, with automatic cross-platform optimization.

### Supported Media Types

- **📷 Images** (`type: :image`) - Photos, screenshots, diagrams
- **📄 Documents** (`type: :document`) - PDFs, forms, receipts  
- **🎥 Videos** (`type: :video`) - Tutorials, demos, explanations
- **🎵 Audio** (`type: :audio`) - Voice messages, recordings
- **😊 Stickers** (`type: :sticker`) - Fun visual elements

### Basic Usage

```ruby
class ProductFlow < FlowChat::Flow
  def main_page
    # ✅ Text input with context image
    feedback = app.screen(:feedback) do |prompt|
      prompt.ask "What do you think of our new product?",
        media: {
          type: :image,
          url: "https://cdn.example.com/products/new_product.jpg"
        }
    end

    # ✅ Send informational media
    app.say "Thanks for your feedback! Here's what's coming next:",
      media: {
        type: :video,
        url: "https://videos.example.com/roadmap.mp4"
      }

    # ✅ Document with filename
    app.say "Here's your receipt:",
      media: {
        type: :document,
        url: "https://api.example.com/receipt.pdf",
        filename: "receipt.pdf"
      }
  end
end
```

### Media Hash Format

```ruby
{
  type: :image,        # Required: :image, :document, :audio, :video, :sticker
  url: "https://...",  # Required: URL to the media file OR WhatsApp media ID
  filename: "doc.pdf"  # Optional: Only for documents
}
```

### Using WhatsApp Media IDs

For better performance and to avoid external dependencies, you can upload files to WhatsApp and use the media ID:

```ruby
# Upload a file first
client = FlowChat::Whatsapp::Client.new(config)
media_id = client.upload_media('path/to/image.jpg', 'image/jpeg')

# Then use the media ID in your flow
app.screen(:product_demo) do |prompt|
  prompt.ask "What do you think?",
    media: {
      type: :image,
      url: media_id  # Use the media ID instead of URL
    }
end
```

### Client Media Methods

The WhatsApp client provides methods for uploading and sending media:

```ruby
client = FlowChat::Whatsapp::Client.new(config)

# Upload media and get media ID
media_id = client.upload_media('image.jpg', 'image/jpeg')
media_id = client.upload_media(file_io, 'image/jpeg', 'photo.jpg')

# Send media directly
client.send_image("+1234567890", "https://example.com/image.jpg", "Caption")
client.send_image("+1234567890", media_id, "Caption")

# Send document with MIME type and filename
client.send_document("+1234567890", "https://example.com/doc.pdf", "Your receipt", "receipt.pdf", "application/pdf")

# Send other media types
client.send_video("+1234567890", "https://example.com/video.mp4", "Demo video", "video/mp4")
client.send_audio("+1234567890", "https://example.com/audio.mp3", "audio/mpeg")
client.send_sticker("+1234567890", "https://example.com/sticker.webp", "image/webp")
```

### Cross-Platform Behavior

**WhatsApp Experience:**
- Media is sent directly to the chat
- Prompt text becomes the media caption
- Rich, native messaging experience

**USSD Experience:**  
- Media URL is included in text message
- Graceful degradation with clear media indicators
- Users can access media via the provided link

```ruby
# This code works on both platforms:
app.screen(:help) do |prompt|
  prompt.ask "Describe your issue:",
    media: {
      type: :image,
      url: "https://support.example.com/help_example.jpg"
    }
end
```

**WhatsApp Result:** Image sent with caption "Describe your issue:"

**USSD Result:** 
```
Describe your issue:

📷 Image: https://support.example.com/help_example.jpg
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

### Background Job Support

For high-volume WhatsApp applications, use background response delivery:

```ruby
# app/jobs/whatsapp_message_job.rb
class WhatsappMessageJob < ApplicationJob
  include FlowChat::Whatsapp::SendJobSupport

  def perform(send_data)
    perform_whatsapp_send(send_data)
  end
end

# config/initializers/flowchat.rb
FlowChat::Config.whatsapp.message_handling_mode = :background
FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'

# config/application.rb
config.active_job.queue_adapter = :sidekiq
```

**The `SendJobSupport` module provides:**
- ✅ **Automatic config resolution** - Resolves named configurations automatically
- ✅ **Response delivery** - Handles sending responses to WhatsApp
- ✅ **Error handling** - Comprehensive error handling with user notifications
- ✅ **Retry logic** - Built-in exponential backoff retry
- ✅ **Extensible** - Override methods for custom behavior

**How it works:**
1. **Controller receives webhook** - WhatsApp message arrives
2. **Flow processes synchronously** - Maintains controller context and session state
3. **Response queued for delivery** - Only the sending is moved to background
4. **Job sends response** - Background job handles API call to WhatsApp

**Advanced job with custom callbacks:**

```ruby
class AdvancedWhatsappMessageJob < ApplicationJob
  include FlowChat::Whatsapp::SendJobSupport

  def perform(send_data)
    perform_whatsapp_send(send_data)
  end

  private

  # Override for custom success handling
  def on_whatsapp_send_success(send_data, result)
    Rails.logger.info "Successfully sent WhatsApp message to #{send_data[:msisdn]}"
    UserEngagementTracker.track_message_sent(phone: send_data[:msisdn])
  end

  # Override for custom error handling
  def on_whatsapp_send_error(error, send_data)
    ErrorTracker.notify(error, user_phone: send_data[:msisdn])
  end
end
```

💡 **See [examples/whatsapp_message_job.rb](examples/whatsapp_message_job.rb) for complete job implementation examples.**

### Middleware Configuration

FlowChat uses a **middleware architecture** to process USSD requests through a configurable pipeline. Each request flows through multiple middleware layers in a specific order.

#### Default Middleware Stack

When you run a flow, FlowChat automatically builds this middleware stack:

```
User Input → Gateway → Session → Pagination → Custom Middleware → Executor → Flow
```

1. **Gateway Middleware** - Handles USSD provider communication (Nalo)
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

### FlowChat Unified Simulator

Use the built-in unified simulator for interactive testing of both USSD and WhatsApp flows:

```ruby
class SimulatorController < ApplicationController
  include FlowChat::Simulator::Controller

  def index
    flowchat_simulator
  end

  protected

  def configurations
    {
      production_ussd: {
        name: "Production USSD",
        icon: "🏭",
        processor_type: "ussd",
        provider: "nalo", 
        endpoint: "/ussd",
        color: "#28a745"
      },
      staging_whatsapp: {
        name: "Staging WhatsApp", 
        icon: "🧪",
        processor_type: "whatsapp",
        provider: "cloud_api",
        endpoint: "/whatsapp/webhook",
        color: "#17a2b8"
      },
      local_ussd: {
        name: "Local USSD",
        icon: "💻", 
        processor_type: "ussd",
        provider: "nalo",
        endpoint: "http://localhost:3000/ussd",
        color: "#6f42c1"
      }
    }
  end

  def default_config_key
    :local_ussd
  end

  def default_phone_number
    "+254712345678"
  end

  def default_contact_name
    "John Doe"
  end
end
```

Add to routes and visit `http://localhost:3000/simulator`.

**Key Features:**
- 🔄 **Platform Toggle** - Switch between USSD and WhatsApp modes with configuration selection
- 📱 **USSD Mode** - Classic green-screen terminal simulation with provider support (Nalo, Nsano)
- 💬 **WhatsApp Mode** - Full WhatsApp interface with interactive buttons, lists, and rich messaging
- ⚙️ **Multi-Environment** - Support for different configurations (local, staging, production)
- 🎨 **Modern UI** - Beautiful, responsive interface with real-time status indicators
- 📊 **Request Logging** - View all HTTP requests and responses in real-time
- 🔧 **Developer Tools** - Character counts, connection status, and comprehensive error handling

The simulator automatically adapts its interface based on the selected configuration:
- **USSD**: Shows traditional terminal-style interface with character limits and pagination
- **WhatsApp**: Displays realistic WhatsApp chat interface with support for interactive elements


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

### 5. Choose the Right WhatsApp Mode

Configure the appropriate mode in your initializer:

```ruby
# config/initializers/flowchat.rb

# Development/Testing - use simulator mode
FlowChat::Config.whatsapp.message_handling_mode = :simulator

# Low-volume Applications - use inline mode  
FlowChat::Config.whatsapp.message_handling_mode = :inline

# High-volume Production - use background mode (sync processing + async sending)
FlowChat::Config.whatsapp.message_handling_mode = :background
FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
```