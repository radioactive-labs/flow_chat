# WhatsApp Development Guide

FlowChat provides comprehensive WhatsApp Business API integration with support for rich media, interactive elements, secure webhook validation, and flexible deployment modes.

## ✨ Key Features

- **Rich Media Support**: Images, documents, audio, video, and stickers
- **Interactive Elements**: Buttons (up to 3), lists (up to 10 items per section)
- **Secure Webhooks**: HMAC-SHA256 signature validation
- **Multiple Processing Modes**: Inline, background, and simulator
- **Media Upload & Download**: Direct file upload and media handling
- **Multi-Tenant Support**: Named configurations for different accounts
- **Development Tools**: Built-in simulator for testing flows

## 🚀 Quick Start

### 1. Basic Setup

Create a WhatsApp controller:

```ruby
# app/controllers/whatsapp_controller.rb
class WhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  rescue => e
    Rails.logger.error "WhatsApp webhook error: #{e.message}"
    head :internal_server_error
  end
end
```

### 2. Add Route

```ruby
# config/routes.rb
post '/whatsapp/webhook', to: 'whatsapp#webhook'
```

### 3. Create a Flow

```ruby
# app/flow_chat/welcome_flow.rb
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
    app.say "📍 Located at 123 Main Street\n🕒 Hours: Mon-Fri 9AM-6PM"
  end

  def contact_support
    app.say "📞 Call us at (555) 123-4567\n📧 Email: support@example.com"
  end

  def collect_feedback
    rating = app.screen(:rating) do |prompt|
      prompt.select "Rate our service:", ["⭐", "⭐⭐", "⭐⭐⭐", "⭐⭐⭐⭐", "⭐⭐⭐⭐⭐"]
    end

    app.say "Thank you for your #{rating} rating! 🙏"
  end
end
```

## 🔧 Configuration

### Option 1: Rails Credentials (Recommended)

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
  skip_signature_validation: false  # Set to true only for development
```

### Option 2: Environment Variables

```bash
export WHATSAPP_ACCESS_TOKEN="your_access_token"
export WHATSAPP_PHONE_NUMBER_ID="your_phone_number_id"
export WHATSAPP_VERIFY_TOKEN="your_verify_token"
export WHATSAPP_APP_ID="your_app_id"
export WHATSAPP_APP_SECRET="your_app_secret"
export WHATSAPP_BUSINESS_ACCOUNT_ID="your_business_account_id"
export WHATSAPP_SKIP_SIGNATURE_VALIDATION="false"
```

### Option 3: Programmatic Configuration

```ruby
config = FlowChat::Whatsapp::Configuration.new(:my_account)
config.access_token = "your_access_token"
config.phone_number_id = "your_phone_number_id"
config.verify_token = "your_verify_token"
config.app_secret = "your_app_secret"
config.skip_signature_validation = false

processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, custom_config
  config.use_session_store FlowChat::Session::CacheSessionStore
end
```

## 📱 Interactive Elements

### Buttons (Up to 3)

FlowChat automatically uses buttons for 3 or fewer choices:

```ruby
def main_menu
  choice = app.screen(:menu) do |prompt|
    prompt.select "What would you like to do?", {
      "balance" => "💰 Check Balance",
      "transfer" => "📤 Transfer Money", 
      "history" => "📜 View History"
    }
  end
  
  handle_choice(choice)
end
```

### Lists (4+ Items)

FlowChat automatically uses interactive lists for more than 3 choices:

```ruby
def product_menu
  product = app.screen(:products) do |prompt|
    prompt.select "Choose a product:", {
      "laptop" => "💻 Laptop - $999",
      "phone" => "📱 Smartphone - $599", 
      "tablet" => "📱 Tablet - $399",
      "watch" => "⌚ Smartwatch - $299",
      "headphones" => "🎧 Headphones - $199"
    }
  end
  
  show_product_details(product)
end
```

Lists support:
- Up to 10 items per section
- Automatic pagination for more items
- Title truncation (24 chars) with full description (72 chars)

## 🎨 Rich Media Support

### Sending Media in Flows

```ruby
def product_showcase
  # Image with prompt
  feedback = app.screen(:product_feedback) do |prompt|
    prompt.ask "What do you think of this product?",
      media: {
        type: :image,
        url: "https://example.com/product.jpg"
      }
  end

  # Document response
  app.say "Thanks! Here's the product catalog:",
    media: {
      type: :document,
      url: "https://example.com/catalog.pdf",
      filename: "product_catalog.pdf"
    }
end

def video_tutorial
  app.say "Watch this tutorial:",
    media: {
      type: :video,
      url: "https://example.com/tutorial.mp4"
    }
end
```

### Media Types Supported

| Type | Usage | Options |
|------|-------|---------|
| `:image` | Photos, screenshots | `url`, `caption` |
| `:document` | PDFs, docs, files | `url`, `caption`, `filename` |
| `:audio` | Voice messages, music | `url`, `caption` |
| `:video` | Video files | `url`, `caption` |
| `:sticker` | Stickers/animated | `url` (no caption) |

### Buttons with Media Headers

```ruby
def media_menu
  choice = app.screen(:options) do |prompt|
    prompt.select "Choose an option:", 
      {
        "details" => "📋 More Details",
        "buy" => "🛒 Buy Now",
        "share" => "📤 Share"
      },
      media: {
        type: :image,
        url: "https://example.com/product.jpg"
      }
  end
end
```

### Handling Incoming Media

```ruby
def handle_media_upload
  if app.media
    media_type = app.media["type"]
    media_id = app.media["id"]
    
    case media_type
    when "image"
      app.say "Thanks for the image! Processing..."
      process_image(media_id)
    when "document"
      app.say "Document received. Reviewing..."
      process_document(media_id)
    when "audio"
      app.say "Got your voice message!"
      process_audio(media_id)
    end
  else
    app.say "Please send a photo of your receipt."
  end
end
```

## 📤 WhatsApp Client API

The `FlowChat::Whatsapp::Client` provides a comprehensive API for sending messages outside of flows and integrating with other systems.

### Client Initialization

```ruby
# From credentials/environment variables
config = FlowChat::Whatsapp::Configuration.from_credentials
client = FlowChat::Whatsapp::Client.new(config)

# Using named configuration
config = FlowChat::Whatsapp::Configuration.get(:my_account)
client = FlowChat::Whatsapp::Client.new(config)
```

### Text Messages

```ruby
# Simple text message
client.send_text("+1234567890", "Hello! How can I help you today?")
```

### Interactive Messages

```ruby
# Interactive buttons (up to 3)
buttons = [
  {id: "option1", title: "View Orders"},
  {id: "option2", title: "Track Package"},
  {id: "option3", title: "Contact Support"}
]
client.send_buttons("+1234567890", "What would you like to do?", buttons)

# Interactive lists (4+ options)
sections = [
  {
    title: "Products",
    rows: [
      {id: "laptop", title: "💻 Laptop", description: "High-performance laptop - $999"},
      {id: "phone", title: "📱 Smartphone", description: "Latest model smartphone - $599"},
      {id: "tablet", title: "📱 Tablet", description: "10-inch tablet - $399"}
    ]
  },
  {
    title: "Accessories", 
    rows: [
      {id: "headphones", title: "🎧 Headphones", description: "Wireless headphones - $199"},
      {id: "case", title: "📱 Phone Case", description: "Protective case - $29"}
    ]
  }
]
client.send_list("+1234567890", "Choose a product:", sections, "Browse")
```

### Media Messages

```ruby
# Send image
client.send_image("+1234567890", "https://example.com/image.jpg", "Check out our new product!")

# Send document  
client.send_document(
  "+1234567890",
  "https://example.com/catalog.pdf", 
  "Here's our product catalog",
  "catalog.pdf"  # optional filename
)

# Send video
client.send_video("+1234567890", "https://example.com/tutorial.mp4", "Watch this tutorial")

# Send audio
client.send_audio("+1234567890", "https://example.com/message.mp3")

# Send sticker (no caption support)
client.send_sticker("+1234567890", "https://example.com/sticker.webp")
```

### Media Upload & Download

```ruby
# Upload local file and get media ID
media_id = client.upload_media("/path/to/file.pdf", "application/pdf", "document.pdf")

# Upload from IO object
File.open("/path/to/image.jpg", "rb") do |file|
  media_id = client.upload_media(file, "image/jpeg", "photo.jpg")
end

# Use uploaded media ID in messages
client.send_document("+1234567890", media_id, "Here's your document")

# Get media URL from ID
media_url = client.get_media_url(media_id)

# Download media content
media_content = client.download_media(media_id)
File.write("/tmp/downloaded_file", media_content, mode: "wb")
```

### Template Messages

```ruby
# Send template message (for conversation initiation)
components = [
  {
    type: "body",
    parameters: [
      {type: "text", text: "John Doe"},
      {type: "text", text: "ORD-12345"}
    ]
  }
]

client.send_template(
  "+1234567890",
  "order_confirmation",
  components,
  "en_US"
)
```

### Complete Service Example

```ruby
# Service for sending notifications
class WhatsappNotificationService
  def initialize(config_name = :default)
    @config = FlowChat::Whatsapp::Configuration.get(config_name)
    @client = FlowChat::Whatsapp::Client.new(@config)
  end

  def send_order_confirmation(phone_number, order_id)
    # Send confirmation message
    @client.send_text(phone_number, "Order ##{order_id} confirmed! 🛍️")
    
    # Send invoice document
    @client.send_document(
      phone_number,
      "https://storage.example.com/invoices/#{order_id}.pdf",
      "Your invoice is ready",
      "invoice_#{order_id}.pdf"
    )
    
    # Send interactive buttons
    @client.send_buttons(phone_number, "What would you like to do next?", [
      {id: "track", title: "Track Order"},
      {id: "support", title: "Contact Support"}, 
      {id: "invoice", title: "View Invoice"}
    ])
  end

  def send_media_gallery(phone_number, images)
    images.each_with_index do |image_url, index|
      @client.send_image(phone_number, image_url, "Image #{index + 1}")
    end
  end

  def send_welcome_message(phone_number, user_name)
    # Upload and send personalized image
    File.open("welcome_images/#{user_name.downcase}.jpg", "rb") do |file|
      media_id = @client.upload_media(file, "image/jpeg", "welcome.jpg")
      @client.send_image(phone_number, media_id, "Welcome #{user_name}! 🎉")
    end
  end
end

# Usage in controllers or background jobs
service = WhatsappNotificationService.new(:main_account)
service.send_order_confirmation("+1234567890", "ORD-123")
```

## 🏗️ Template Manager

The `FlowChat::Whatsapp::TemplateManager` provides utilities for managing WhatsApp message templates, which are required for initiating conversations with users.

### Template Manager Setup

```ruby
# Using default configuration
template_manager = FlowChat::Whatsapp::TemplateManager.new

# Using specific configuration
config = FlowChat::Whatsapp::Configuration.get(:my_account)
template_manager = FlowChat::Whatsapp::TemplateManager.new(config)
```

### Sending Template Messages

```ruby
# Basic template message
template_manager.send_template(
  to: "+1234567890",
  template_name: "hello_world",
  language: "en_US",
  components: []
)

# Template with parameters
components = [
  {
    type: "body",
    parameters: [
      {type: "text", text: "John Doe"},
      {type: "text", text: "Order #12345"}
    ]
  }
]

template_manager.send_template(
  to: "+1234567890", 
  template_name: "order_update",
  language: "en_US",
  components: components
)
```

### Pre-built Template Methods

```ruby
# Send welcome template (uses Meta's default hello_world template)
template_manager.send_welcome_template(
  to: "+1234567890",
  name: "John Doe"  # Optional personalization
)

# Send notification template
template_manager.send_notification_template(
  to: "+1234567890",
  message: "Your order has shipped! Track it with the link below.",
  button_text: "Track Package"  # Optional quick reply button
)
```

### Template Management

```ruby
# Create a new template (requires Meta approval)
template_manager.create_template(
  name: "order_confirmation",
  category: "UTILITY",  # AUTHENTICATION, MARKETING, UTILITY
  language: "en_US",
  components: [
    {
      type: "HEADER",
      format: "TEXT",
      text: "Order Confirmed"
    },
    {
      type: "BODY", 
      text: "Hi {{1}}, your order {{2}} has been confirmed and will arrive by {{3}}."
    },
    {
      type: "FOOTER",
      text: "Thank you for shopping with us!"
    },
    {
      type: "BUTTONS",
      buttons: [
        {
          type: "QUICK_REPLY",
          text: "Track Order"
        },
        {
          type: "QUICK_REPLY", 
          text: "Cancel Order"
        }
      ]
    }
  ]
)

# List all templates
templates = template_manager.list_templates
templates["data"].each do |template|
  puts "Template: #{template["name"]} - Status: #{template["status"]}"
end

# Check template status
status = template_manager.template_status("template_id_here")
puts "Template status: #{status["status"]}"  # PENDING, APPROVED, REJECTED
```

### Template Categories

- **AUTHENTICATION**: One-time passwords, account verification
- **MARKETING**: Promotional messages, newsletters (requires opt-in)
- **UTILITY**: Order updates, appointment reminders, account notifications

### Template Components

```ruby
# Complete template structure example
components = [
  # Header (optional)
  {
    type: "HEADER",
    format: "TEXT",  # or IMAGE, VIDEO, DOCUMENT
    text: "Your Receipt"
  },
  
  # Body (required)
  {
    type: "BODY",
    text: "Hi {{1}}, here's your receipt for order {{2}} totaling {{3}}."
  },
  
  # Footer (optional)
  {
    type: "FOOTER", 
    text: "Questions? Reply to this message."
  },
  
  # Buttons (optional)
  {
    type: "BUTTONS",
    buttons: [
      {
        type: "QUICK_REPLY",
        text: "Download PDF"
      },
      {
        type: "URL",
        text: "View Online",
        url: "https://example.com/receipt/{{1}}"
      },
      {
        type: "PHONE_NUMBER",
        text: "Call Support",
        phone_number: "+1234567890"
      }
    ]
  }
]
```

### Integration with Services

```ruby
class OrderNotificationService
  def initialize
    @template_manager = FlowChat::Whatsapp::TemplateManager.new
  end

  def notify_order_confirmed(order)
    @template_manager.send_template(
      to: order.customer_phone,
      template_name: "order_confirmation",
      language: order.customer_locale || "en_US",
      components: [
        {
          type: "body",
          parameters: [
            {type: "text", text: order.customer_name},
            {type: "text", text: order.id},
            {type: "text", text: order.estimated_delivery.strftime("%B %d")}
          ]
        }
      ]
    )
  end

  def notify_order_shipped(order)
    @template_manager.send_notification_template(
      to: order.customer_phone,
      message: "Great news! Order #{order.id} has shipped and is on its way.",
      button_text: "Track Package"
    )
  end
end
```

## 📁 Media Upload & Download

### Uploading Files

```ruby
# Upload local file
client = FlowChat::Whatsapp::Client.new(config)
media_id = client.upload_media("/path/to/file.pdf", "application/pdf", "document.pdf")

# Upload from IO
File.open("/path/to/image.jpg", "rb") do |file|
  media_id = client.upload_media(file, "image/jpeg", "photo.jpg")
end

# Use uploaded media ID
client.send_document("+1234567890", media_id, "Here's your document")
```

### Downloading Media

```ruby
# Get media URL from ID
media_url = client.get_media_url(media_id)

# Download media content
media_content = client.download_media(media_id)

# Save to file
File.write("/tmp/downloaded_media", media_content, mode: "wb")
```

## ⚙️ Processing Modes

FlowChat supports three distinct message processing modes to handle different deployment scenarios and performance requirements. Configure the mode in your initializer:

```ruby
# config/initializers/flowchat.rb
FlowChat::Config.whatsapp.message_handling_mode = :inline  # Default
```

### Mode Comparison

| Feature | Inline | Background | Simulator |
|---------|--------|------------|-----------|
| **Response Speed** | Immediate | Async (queued) | Immediate |
| **Webhook Timeout Risk** | High | None | None |
| **Scalability** | Limited | High | N/A (testing only) |
| **Setup Complexity** | Simple | Moderate | Simple |
| **Production Ready** | Yes | Yes | No (development only) |
| **Debugging** | Easy | Moderate | Easy |
| **Message Delivery** | Real WhatsApp | Real WhatsApp | Simulated |

### Inline Mode (Default)

Messages are processed synchronously:

```ruby
FlowChat::Config.whatsapp.message_handling_mode = :inline
```

**Pros**: Simple, immediate responses  
**Cons**: Webhook timeouts for slow operations

### Background Mode

Flow processing is synchronous, but responses are sent asynchronously using background jobs:

```ruby
FlowChat::Config.whatsapp.message_handling_mode = :background
FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
```

Create a background job using the `SendJobSupport` module:

```ruby
# app/jobs/whatsapp_message_job.rb
class WhatsappMessageJob < ApplicationJob
  include FlowChat::Whatsapp::SendJobSupport

  # The perform method is automatically handled by SendJobSupport
  # It calls perform_whatsapp_send(send_data) with the proper data structure

  # Optional: Override for custom success handling
  def on_whatsapp_send_success(send_data, result)
    # Log successful delivery, update database, etc.
    Rails.logger.info "Message delivered to #{send_data[:msisdn]}: #{result}"
  end

  # Optional: Override for custom error handling  
  def on_whatsapp_send_error(error, send_data)
    # Custom error handling, notification, etc.
    ErrorTracker.notify(error, context: { phone: send_data[:msisdn] })
  end
end
```

#### SendJobSupport Features

The `FlowChat::Whatsapp::SendJobSupport` module provides:

- **Automatic configuration resolution**: Resolves configurations by name or falls back to defaults
- **Built-in retry logic**: Exponential backoff with 3 retry attempts
- **Error handling**: Automatic user notification on persistent failures
- **Instrumentation**: Logging and monitoring integration
- **Graceful degradation**: Attempts to notify users of failures when possible

#### Manual Background Job Implementation

If you prefer not to use `SendJobSupport`, you can implement manually:

```ruby
# app/jobs/custom_whatsapp_job.rb
class CustomWhatsappJob < ApplicationJob
  queue_as :whatsapp
  retry_on StandardError, wait: :exponentially_longer, attempts: 5

  def perform(send_data)
    config = resolve_config(send_data)
    client = FlowChat::Whatsapp::Client.new(config)
    
    result = client.send_message(send_data[:msisdn], send_data[:response])
    
    unless result
      raise "WhatsApp API call failed for #{send_data[:msisdn]}"
    end
    
    Rails.logger.info "WhatsApp message sent: #{result["messages"]&.first&.dig("id")}"
  end

  private

  def resolve_config(send_data)
    if send_data[:config_name]
      FlowChat::Whatsapp::Configuration.get(send_data[:config_name])
    else
      FlowChat::Whatsapp::Configuration.from_credentials
    end
  end
end
```

#### Background Job Data Structure

The background job receives a `send_data` hash with:

```ruby
send_data = {
  msisdn: "+1234567890",           # Recipient phone number
  response: [:text, "Hello!", {}], # FlowChat response format
  config_name: :my_account,        # Optional: Named configuration
  metadata: {                      # Optional: Additional context
    user_id: 123,
    flow_name: "WelcomeFlow",
    session_id: "abc123"
  }
}
```

**Pros**: No webhook timeouts, scalable, reliable  
**Cons**: Slightly more complex setup, async responses

### Simulator Mode

Returns response data instead of sending via WhatsApp API, perfect for development and testing:

```ruby
FlowChat::Config.whatsapp.message_handling_mode = :simulator
```

#### Simulator Features

- **No API calls**: Messages are not sent to WhatsApp
- **Response inspection**: Returns full message payload in HTTP response
- **Flow debugging**: Test conversation flows without real phone numbers
- **No webhook validation**: Bypasses signature validation for easier testing
- **Fast iteration**: Immediate feedback without waiting for WhatsApp delivery

#### Simulator Response Format

Instead of sending to WhatsApp, the simulator returns JSON with the message payload:

```json
{
  "mode": "simulator",
  "message_sent": true,
  "response_data": {
    "messaging_product": "whatsapp",
    "to": "+1234567890",
    "type": "interactive",
    "interactive": {
      "type": "button",
      "body": {"text": "What would you like to do?"},
      "action": {
        "buttons": [
          {"type": "reply", "reply": {"id": "option1", "title": "View Orders"}},
          {"type": "reply", "reply": {"id": "option2", "title": "Track Package"}}
        ]
      }
    }
  },
  "config_used": "default",
  "timestamp": "2024-01-15T10:30:00Z"
}
```

#### Using Simulator in Development

```ruby
# Enable simulator conditionally
processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
  config.use_session_store FlowChat::Session::CacheSessionStore
end

# Set mode globally in development
FlowChat::Config.whatsapp.message_handling_mode = Rails.env.development? ? :simulator : :inline

# Or enable per-request (useful for testing)
# Add ?simulator=true to webhook URL for one-off testing
```

#### Testing with Simulator

```ruby
# test/integration/whatsapp_simulator_test.rb
class WhatsappSimulatorTest < ActionDispatch::IntegrationTest
  def setup
    # Force simulator mode for tests
    @original_mode = FlowChat::Config.whatsapp.message_handling_mode
    FlowChat::Config.whatsapp.message_handling_mode = :simulator
  end

  def teardown
    FlowChat::Config.whatsapp.message_handling_mode = @original_mode
  end

  def test_welcome_flow_buttons
    # Simulate WhatsApp webhook
    webhook_data = {
      entry: [{
        changes: [{
          value: {
            messages: [{
              from: "1234567890",
              id: "msg_123",
              type: "text",
              text: { body: "hello" }
            }],
            contacts: [{
              profile: { name: "Test User" }
            }]
          }
        }]
      }]
    }

    post "/whatsapp/webhook", params: webhook_data

    assert_response :success
    response_json = JSON.parse(response.body)
    
    assert_equal "simulator", response_json["mode"]
    assert_equal "interactive", response_json["response_data"]["type"]
    assert response_json["response_data"]["interactive"]["action"]["buttons"].present?
  end
end
```

**Pros**: Perfect for testing, fast development, no API costs, detailed response inspection  
**Cons**: Messages aren't actually sent, doesn't test real WhatsApp behavior

## 🔒 Security & Validation

### Webhook Signature Validation

FlowChat automatically validates WhatsApp webhook signatures using HMAC-SHA256 to ensure requests are genuinely from WhatsApp and haven't been tampered with.

#### How Signature Validation Works

```ruby
# 1. Extract signature from X-Hub-Signature-256 header
# 2. Calculate HMAC-SHA256 hash of request body using app_secret
# 3. Compare calculated signature with provided signature using secure comparison
# 4. Reject request if signatures don't match
```

#### Production Configuration (Required)

```ruby
# config/credentials/production.yml
whatsapp:
  app_secret: "your_whatsapp_app_secret_from_meta"
  # ... other settings

# The gateway automatically validates signatures
processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
  # Signature validation is enabled by default
end
```

#### Development Configuration Options

```ruby
# Option 1: Use real app_secret (recommended for staging)
config = FlowChat::Whatsapp::Configuration.new
config.app_secret = "your_whatsapp_app_secret"
config.skip_signature_validation = false  # Default behavior

# Option 2: Explicitly disable validation (development only)
config = FlowChat::Whatsapp::Configuration.new
config.app_secret = nil  # Not required when disabled
config.skip_signature_validation = true  # Must be explicitly set to true

# Option 3: Environment-based configuration
config = FlowChat::Whatsapp::Configuration.new
config.app_secret = Rails.env.production? ? "real_secret" : nil
config.skip_signature_validation = !Rails.env.production?
```

#### Configuration Error Handling

The gateway will raise `FlowChat::Whatsapp::ConfigurationError` if:

```ruby
# Missing app_secret with validation enabled (default)
# Error: "WhatsApp app_secret is required for webhook signature validation"

# Invalid webhook signature received
# Returns HTTP 401 Unauthorized

# Valid configuration examples:
config.app_secret = "secret"; config.skip_signature_validation = false  # ✅ Secure
config.app_secret = nil; config.skip_signature_validation = true        # ✅ Explicitly disabled
config.app_secret = "secret"; config.skip_signature_validation = true   # ✅ Secret provided but validation disabled

# Invalid configuration:  
config.app_secret = nil; config.skip_signature_validation = false       # ❌ Error
```

#### Security Implementation Details

```ruby
# The gateway uses secure comparison to prevent timing attacks
def valid_webhook_signature?(request)
  # Extract signature from X-Hub-Signature-256 header
  signature_header = request.headers["X-Hub-Signature-256"]
  expected_signature = signature_header.sub("sha256=", "")
  
  # Calculate HMAC-SHA256 of request body
  body = request.body.read
  calculated_signature = OpenSSL::HMAC.hexdigest(
    OpenSSL::Digest.new("SHA256"), 
    @config.app_secret, 
    body
  )
  
  # Use secure comparison to prevent timing attacks
  ActiveSupport::SecurityUtils.secure_compare(expected_signature, calculated_signature)
end
```

⚠️ **Security Warning**: Never disable signature validation in production environments.

### Error Handling

```ruby
def webhook
  processor = FlowChat::Processor.new(self) do |config|
    config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
    config.use_session_store FlowChat::Session::CacheSessionStore
  end

  processor.run WelcomeFlow, :main_page
rescue FlowChat::Whatsapp::ConfigurationError => e
  Rails.logger.error "WhatsApp configuration error: #{e.message}"
  head :internal_server_error
rescue => e
  Rails.logger.error "WhatsApp webhook error: #{e.message}"
  head :internal_server_error
end
```

### Configuration Validation

FlowChat will raise a `ConfigurationError` if:
- `app_secret` is missing and validation is not explicitly disabled
- Required credentials are missing
- Invalid webhook signatures are received

## 🏢 Multi-Tenant Support

### Named Configurations

Register configurations by name for different accounts:

```ruby
# config/initializers/whatsapp_configs.rb
tenant_a_config = FlowChat::Whatsapp::Configuration.new(:tenant_a)
tenant_a_config.access_token = "tenant_a_token"
tenant_a_config.phone_number_id = "tenant_a_phone"
tenant_a_config.verify_token = "tenant_a_verify"
tenant_a_config.app_secret = "tenant_a_secret"

tenant_b_config = FlowChat::Whatsapp::Configuration.new(:tenant_b)
tenant_b_config.access_token = "tenant_b_token"
tenant_b_config.phone_number_id = "tenant_b_phone"
tenant_b_config.verify_token = "tenant_b_verify"
tenant_b_config.app_secret = "tenant_b_secret"
```

### Configuration API

The configuration system provides several methods for managing named configurations:

```ruby
# Check if a configuration exists
FlowChat::Whatsapp::Configuration.exists?(:tenant_a)  # => true/false

# Get configuration by name (raises error if not found)
config = FlowChat::Whatsapp::Configuration.get(:tenant_a)

# Get configuration with fallback
config = FlowChat::Whatsapp::Configuration.get(:tenant_a) rescue FlowChat::Whatsapp::Configuration.from_credentials

# Register configuration programmatically
config = FlowChat::Whatsapp::Configuration.new(:dynamic_tenant)
config.access_token = "token_here"
config.phone_number_id = "phone_id_here"
# ... other settings
```

### Using Named Configurations

```ruby
class MultiTenantWhatsappController < ApplicationController
  def webhook
    tenant = determine_tenant(request)
    
    # Verify configuration exists
    unless FlowChat::Whatsapp::Configuration.exists?(tenant)
      Rails.logger.error "No WhatsApp configuration found for tenant: #{tenant}"
      head :not_found
      return
    end
    
    whatsapp_config = FlowChat::Whatsapp::Configuration.get(tenant)
    
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, whatsapp_config
      config.use_session_store FlowChat::Session::CacheSessionStore
      # Use tenant-specific session boundaries
      config.use_session_config(
        boundaries: [:flow, :platform, :tenant],
        identifier: :msisdn,
        tenant: tenant
      )
    end

    processor.run WelcomeFlow, :main_page
  end

  private

  def determine_tenant(request)
    # Multiple strategies for tenant detection
    if request.subdomain.present?
      request.subdomain.to_sym
    elsif request.path.start_with?('/api/')
      # Extract from API path: /api/v1/tenants/acme/whatsapp
      request.path.split('/')[4]&.to_sym
    elsif request.headers['X-Tenant-ID'].present?
      request.headers['X-Tenant-ID'].to_sym
    else
      :default
    end
  end
end
```

### Background Jobs with Multi-Tenancy

```ruby
class WhatsappMessageJob < ApplicationJob
  include FlowChat::Whatsapp::SendJobSupport

  # SendJobSupport automatically handles configuration resolution
  # It will use send_data[:config_name] if provided, otherwise fallback to default

  def on_whatsapp_send_success(send_data, result)
    # Log with tenant context
    tenant = send_data[:config_name] || :default
    Rails.logger.info "Message sent for tenant #{tenant}: #{result["messages"]&.first&.dig("id")}"
  end
end
```

### Dynamic Configuration Management

```ruby
class TenantConfigurationService
  def self.setup_tenant(tenant_name, credentials)
    config = FlowChat::Whatsapp::Configuration.new(tenant_name)
    config.access_token = credentials[:access_token]
    config.phone_number_id = credentials[:phone_number_id] 
    config.verify_token = credentials[:verify_token]
    config.app_secret = credentials[:app_secret]
    config.business_account_id = credentials[:business_account_id]
    
    # Validate configuration before registering
    unless config.valid?
      raise "Invalid WhatsApp configuration for tenant: #{tenant_name}"
    end
    
    Rails.logger.info "WhatsApp configuration registered for tenant: #{tenant_name}"
  end

  def self.remove_tenant(tenant_name)
    # Note: The current implementation doesn't provide a removal method
    # This would need to be added to the Configuration class
    Rails.logger.info "TODO: Remove configuration for tenant: #{tenant_name}"
  end
end

# Usage in tenant onboarding
TenantConfigurationService.setup_tenant(:new_client, {
  access_token: "EAAxxxxxxxxx",
  phone_number_id: "1234567890",
  verify_token: "my_verify_token",
  app_secret: "app_secret_here",
  business_account_id: "business_account_id"
})
```

## 🧪 Testing & Development

### Simulator Mode

Enable the simulator for testing during development:

```ruby
# Enable simulator in development
processor = FlowChat::Processor.new(self, enable_simulator: Rails.env.development?) do |config|
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
  config.use_session_store FlowChat::Session::CacheSessionStore  
end
```

The simulator provides:
- Web interface for testing flows
- No actual WhatsApp API calls
- Response data returned in HTTP response
- Secure cookie-based authentication

### Testing Flows

```ruby
# test/flow_chat/welcome_flow_test.rb
require 'test_helper'

class WelcomeFlowTest < ActiveSupport::TestCase
  include FlowChat::TestHelpers

  def test_main_page_flow
    # Simulate WhatsApp input
    session = create_test_session
    app = create_test_app(session: session)
    flow = WelcomeFlow.new(app)

    # Test the flow
    simulate_input(app, "John")
    simulate_input(app, "info")
    
    response = flow.main_page
    
    assert_includes response.last, "Located at 123 Main Street"
  end
end
```

## 📊 Instrumentation & Monitoring

FlowChat includes built-in instrumentation for WhatsApp events:

```ruby
# Events automatically tracked:
# - FlowChat::Events::MESSAGE_RECEIVED
# - FlowChat::Events::MESSAGE_SENT  
# - FlowChat::Events::MEDIA_UPLOAD
# - FlowChat::Events::WEBHOOK_VERIFIED
# - FlowChat::Events::WEBHOOK_FAILED

# Custom instrumentation
FlowChat.instrument("custom.whatsapp.event", {
  user_id: app.user_id,
  action: "custom_action",
  metadata: { key: "value" }
})
```

## 🚨 Troubleshooting

### Common Issues

**1. Configuration Error: app_secret required**
```
WhatsApp app_secret is required for webhook signature validation.
```
**Solution**: Configure `WHATSAPP_APP_SECRET` or disable validation explicitly.

**2. Invalid webhook signature**
```
Invalid webhook signature received
```
**Solution**: Verify your `app_secret` matches your WhatsApp app configuration.

**3. Media upload fails**
```
Media upload failed: Invalid mime type
```
**Solution**: Ensure MIME type is correctly specified and supported.

**4. Background job class not found**
```
Background mode requested but no WhatsappMessageJob found
```
**Solution**: Create the background job class or use inline mode.

### Debug Mode

Enable debug logging:

```ruby
# config/environments/development.rb
config.log_level = :debug

# This will log:
# - Webhook signature validation
# - Message parsing and extraction
# - API request/response details
# - Configuration loading
```

### Environment-Specific Configuration

```ruby
# config/initializers/flowchat.rb
case Rails.env
when 'development'
  FlowChat::Config.whatsapp.message_handling_mode = :simulator
  # Skip signature validation for easier testing
  
when 'test'
  FlowChat::Config.whatsapp.message_handling_mode = :simulator
  
when 'staging'
  FlowChat::Config.whatsapp.message_handling_mode = :inline
  # Full security validation
  
when 'production'
  FlowChat::Config.whatsapp.message_handling_mode = :background
  FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
  # Maximum security and scalability
end
```

## 🎯 Best Practices

### 1. Message Design
- Keep button titles under 20 characters
- Use clear, actionable text
- Include relevant emojis for visual appeal
- Test across different devices

### 2. Media Usage
- Use appropriate file sizes (< 16MB for documents)
- Provide descriptive captions
- Use supported formats (JPEG, PNG for images; PDF for documents)
- Consider bandwidth limitations

### 3. Flow Design
- Handle media uploads gracefully
- Provide clear error messages
- Use progressive disclosure for complex flows
- Test with real user scenarios

### 4. Security
- Always validate webhooks in production
- Use environment variables for secrets
- Log security events appropriately
- Monitor for unusual patterns

### 5. Performance
- Use background processing for heavy operations
- Cache frequently used data
- Monitor response times
- Handle timeouts gracefully

## 📚 API Reference

### Core Classes

- `FlowChat::Whatsapp::Gateway::CloudApi` - Main gateway implementation
- `FlowChat::Whatsapp::Client` - Direct API client for out-of-band messaging
- `FlowChat::Whatsapp::Configuration` - Configuration management
- `FlowChat::Whatsapp::Renderer` - Message rendering logic

### Client Methods

| Method | Description | Parameters |
|--------|-------------|------------|
| `send_message(to, response)` | Send FlowChat response format | phone, response array |
| `send_text(to, text)` | Send text message | phone, message |
| `send_buttons(to, text, buttons)` | Send interactive buttons | phone, text, button array |
| `send_list(to, text, sections, button_text)` | Send interactive list | phone, text, sections, button text |
| `send_template(to, name, components, language)` | Send template message | phone, template name, components, language |
| `send_image(to, url_or_id, caption, mime_type)` | Send image | phone, url/media ID, caption, mime type |
| `send_document(to, url_or_id, caption, filename, mime_type)` | Send document | phone, url/media ID, caption, filename, mime type |
| `send_video(to, url_or_id, caption, mime_type)` | Send video | phone, url/media ID, caption, mime type |
| `send_audio(to, url_or_id, mime_type)` | Send audio | phone, url/media ID, mime type |
| `send_sticker(to, url_or_id, mime_type)` | Send sticker | phone, url/media ID, mime type |
| `upload_media(file_path_or_io, mime_type, filename)` | Upload file and get media ID | file path/IO, mime type, filename |
| `get_media_url(media_id)` | Get media URL from ID | media ID |
| `download_media(media_id)` | Download media content | media ID |
| `build_message_payload(response, to)` | Build WhatsApp API payload | FlowChat response, phone number |

### Template Manager Methods

| Method | Description | Parameters |
|--------|-------------|------------|
| `send_template(to:, template_name:, language:, components:)` | Send template message | named parameters |
| `send_welcome_template(to:, name:)` | Send welcome template | phone, optional name |
| `send_notification_template(to:, message:, button_text:)` | Send notification template | phone, message, optional button |
| `create_template(name:, category:, language:, components:)` | Create new template | template details |
| `list_templates()` | List all templates | none |
| `template_status(template_id)` | Get template status | template ID |

### Configuration Methods

| Method | Description | Parameters |
|--------|-------------|------------|
| `Configuration.from_credentials()` | Load from Rails credentials/ENV | none |
| `Configuration.new(name)` | Create named configuration | configuration name |
| `Configuration.register(name, config)` | Register configuration | name, config object |
| `Configuration.get(name)` | Get configuration by name | configuration name |
| `Configuration.exists?(name)` | Check if config exists | configuration name |

---

This comprehensive guide covers everything you need to build sophisticated WhatsApp integrations with FlowChat. For more examples and advanced patterns, check the [examples directory](../../examples/) in the FlowChat repository.