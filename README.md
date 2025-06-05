# FlowChat

FlowChat is a Rails framework designed for building sophisticated conversational workflows for both USSD (Unstructured Supplementary Service Data) systems and WhatsApp messaging. It provides an intuitive Ruby DSL for creating multi-step, menu-driven conversations with automatic session management, input validation, and flow control.

**Key Features:**
- 🎯 **Declarative Flow Definition** - Define conversation flows as Ruby classes
- 🔄 **Automatic Session Management** - Persistent state across requests  
- ✅ **Input Validation & Transformation** - Built-in validation and data conversion
- 🌊 **Middleware Architecture** - Flexible request processing pipeline
- 📱 **USSD Gateway Support** - Currently supports Nalo gateways
- 💬 **WhatsApp Integration** - Full WhatsApp Cloud API support with multiple processing modes and webhook signature validation
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
  skip_signature_validation: false  # Set to true only for development/testing
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
export WHATSAPP_SKIP_SIGNATURE_VALIDATION="false"  # Set to "true" only for development/testing
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
custom_config.skip_signature_validation = false  # Security setting

# Use in processor
processor = FlowChat::Whatsapp::Processor.new(self) do |config|
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, custom_config
  config.use_session_store FlowChat::Session::CacheSessionStore
end
```

💡 **Tip**: See [examples/multi_tenant_whatsapp_controller.rb](examples/multi_tenant_whatsapp_controller.rb) for comprehensive multi-tenant and per-setup configuration examples.

### 2. Security Configuration

FlowChat includes robust security features for WhatsApp webhook validation:

**Webhook Signature Validation** (Recommended for Production)

FlowChat automatically validates WhatsApp webhook signatures using your app secret:

```ruby
# config/initializers/flowchat.rb

# Global security configuration
FlowChat::Config.simulator_secret = "your_secure_random_secret_for_simulator"

# WhatsApp security is configured per-configuration
# The app_secret from your WhatsApp configuration is used for webhook validation
```

**Security Options:**

```ruby
# Option 1: Full security (recommended for production)
custom_config.app_secret = "your_whatsapp_app_secret"  # Required for signature validation
custom_config.skip_signature_validation = false       # Default: enforce validation

# Option 2: Disable validation (development/testing only)
custom_config.app_secret = nil                        # Not required when disabled
custom_config.skip_signature_validation = true        # Explicitly disable validation
```

⚠️ **Security Warning**: Only disable signature validation in development/testing environments. Production environments should always validate webhook signatures using your WhatsApp app secret.

**Simulator Authentication**

The simulator mode requires authentication:

```ruby
# config/initializers/flowchat.rb
FlowChat::Config.simulator_secret = Rails.application.secret_key_base + "_simulator"

# Or use a dedicated secret
FlowChat::Config.simulator_secret = "your_secure_random_secret_here"
```

The simulator uses HMAC-SHA256 signed cookies for authentication with 24-hour expiration.

📚 **For comprehensive security documentation, see [SECURITY.md](SECURITY.md)**

### 3. Choose Message Handling Mode

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

### 4. Add WhatsApp Route

```ruby
Rails.application.routes.draw do
  match '/whatsapp/webhook', to: 'whatsapp#webhook', via: [:get, :post]
end
```

### 5. Enhanced Simulator Setup

FlowChat provides a powerful built-in simulator for testing flows in both USSD and WhatsApp modes.

**Setup Simulator Controller:**

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
      local_whatsapp: {
        name: "Local WhatsApp",
        icon: "💬",
        processor_type: "whatsapp",
        provider: "cloud_api",
        endpoint: "/whatsapp/webhook",
        color: "#25D366"
      },
      local_ussd: {
        name: "Local USSD",
        icon: "📱",
        processor_type: "ussd",
        provider: "nalo",
        endpoint: "/ussd",
        color: "#007bff"
      },
      staging_whatsapp: {
        name: "Staging WhatsApp",
        icon: "🧪",
        processor_type: "whatsapp",
        provider: "cloud_api",
        endpoint: "https://staging.yourapp.com/whatsapp/webhook",
        color: "#17a2b8"
      }
    }
  end

  def default_config_key
    :local_whatsapp
  end

  def default_phone_number
    "+1234567890"
  end

  def default_contact_name
    "John Doe"
  end
end
```

**Add Simulator Route:**

```ruby
# config/routes.rb
Rails.application.routes.draw do
  get '/simulator' => 'simulator#index'
  # ... other routes
end
```

**Configure Simulator Security:**

```ruby
# config/initializers/flowchat.rb
FlowChat::Config.simulator_secret = Rails.application.secret_key_base + "_simulator"
```

**Enable Simulator Mode in Controllers:**

For controllers that should support simulator mode, enable it in the processor:

```ruby
# app/controllers/whatsapp_controller.rb
class WhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Whatsapp::Processor.new(self, enable_simulator: Rails.env.local?) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
  end
end
```

This is enabled by default in `Rails.env.local?` (development and testing) environments.

**Simulator Features:**
- 🔄 **Platform Toggle** - Switch between USSD and WhatsApp modes
- 📱 **USSD Mode** - Classic terminal simulation with pagination
- 💬 **WhatsApp Mode** - Full WhatsApp interface with interactive elements
- ⚙️ **Multi-Environment** - Support for different configurations
- 🎨 **Modern UI** - Beautiful, responsive interface
- 📊 **Request Logging** - View HTTP requests and responses in real-time
- 🔧 **Developer Tools** - Character counts, connection status, error handling
- 🔒 **Secure Authentication** - HMAC-signed cookies with expiration

Visit `http://localhost:3000/simulator` to access the simulator interface.

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

FlowChat provides comprehensive testing capabilities for both USSD and WhatsApp flows. This section covers all testing approaches from simple unit tests to complex integration scenarios.

### Testing Approaches Overview

FlowChat supports two main testing strategies:

**🎯 Option 1: Simulator Mode (Recommended)**
- Bypasses WhatsApp API entirely
- No webhook signature validation required  
- Responses returned as JSON instead of sent to WhatsApp
- Perfect for unit and integration testing
- Works with built-in web simulator interface

**🔒 Option 2: Skip Signature Validation**
- Tests real webhook endpoints without security complexity
- Useful for staging environments
- Set `skip_signature_validation = true`

### Environment-Specific Testing Configuration

Configure testing behavior per environment:

```ruby
# config/initializers/flowchat.rb
case Rails.env
when 'development', 'test'
  # Use simulator mode for easy testing
  FlowChat::Config.whatsapp.message_handling_mode = :simulator
  FlowChat::Config.simulator_secret = Rails.application.secret_key_base + "_#{Rails.env}"
  
when 'staging'
  # Test real webhooks but skip validation for easier setup
  FlowChat::Config.whatsapp.message_handling_mode = :inline
  # Individual configurations can set skip_signature_validation = true
  
when 'production'
  # Full security - never skip validation
  FlowChat::Config.whatsapp.message_handling_mode = :background
  FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
end
```

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

#### Simulator Mode Testing

Test complete flows using simulator mode with authentication:

```ruby
require 'test_helper'

class WhatsappIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    # Configure test credentials
    FlowChat::Config.simulator_secret = "test_secret"
    @app_secret = "test_app_secret_for_webhook_validation"
  end

  test "complete flow via simulator" do
    # Generate valid simulator cookie for authentication
    valid_cookie = generate_simulator_cookie
    
    # Create webhook payload
    webhook_payload = {
      entry: [{
        changes: [{
          value: {
            messages: [{
              from: "1234567890",
              text: { body: "Hello" },
              type: "text",
              id: "wamid.test123"
            }]
          }
        }]
      }],
      simulator_mode: true
    }

    post "/whatsapp/webhook", 
      params: webhook_payload,
      cookies: { flowchat_simulator: valid_cookie }

    assert_response :success
    response_data = JSON.parse(response.body)
    assert_equal "simulator", response_data["mode"]
    assert response_data["webhook_processed"]
  end
end
```

#### Testing with Skipped Validation

For testing real webhook processing without signature complexity:

```ruby
test "webhook processing with skipped validation" do
  # Configure controller to skip validation
  config = FlowChat::Whatsapp::Configuration.new
  config.access_token = "test_token"
  config.phone_number_id = "test_phone_id"
  config.skip_signature_validation = true  # Skip for testing

  webhook_payload = {
    entry: [{
      changes: [{
        value: {
          messages: [{
            from: "1234567890",
            text: { body: "Test message" },
            type: "text"
          }]
        }
      }]
    }]
  }

  # No signature required when validation is skipped
  post "/whatsapp/webhook", 
    params: webhook_payload.to_json,
    headers: { "Content-Type" => "application/json" }

  assert_response :success
end
```

### Security Testing

Test webhook signature validation when security is enabled:

#### Valid Signature Testing

```ruby
test "webhook accepts valid signature" do
  webhook_payload = {
    entry: [{
      changes: [{
        value: {
          messages: [{
            from: "1234567890",
            text: { body: "Hello from webhook" },
            type: "text",
            id: "wamid.real_webhook_123"
          }]
        }
      }]
    }]
  }
  
  # Convert to JSON for signature calculation
  payload_json = webhook_payload.to_json
  
  # Generate valid HMAC-SHA256 signature using helper
  signature = generate_webhook_signature(payload_json)

  post "/whatsapp/webhook",
    params: payload_json,
    headers: { 
      "Content-Type" => "application/json",
      "X-Hub-Signature-256" => "sha256=#{signature}"
    }

  assert_response :success
end
```

#### Invalid Signature Testing

```ruby
test "webhook rejects invalid signature" do
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
    headers: { 
      "Content-Type" => "application/json",
      "X-Hub-Signature-256" => "sha256=invalid_signature_here" 
    }

  assert_response :unauthorized
end

test "webhook rejects missing signature" do
  webhook_payload = create_valid_webhook_payload("Test message")

  post "/whatsapp/webhook", 
    params: webhook_payload.to_json,
    headers: { "Content-Type" => "application/json" }
    # No X-Hub-Signature-256 header

  assert_response :unauthorized
end
```

### Test Configuration Examples

#### Simulator Mode Configuration

```ruby
# For testing only - enable simulator mode
FlowChat::Config.whatsapp.message_handling_mode = :simulator
FlowChat::Config.simulator_secret = Rails.application.secret_key_base + "_dev"

# In controller for testing
processor = FlowChat::Whatsapp::Processor.new(self, enable_simulator: Rails.env.local?) do |config|
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
  config.use_session_store FlowChat::Session::CacheSessionStore
end
```

#### Skip Validation Configuration

```ruby
# For testing only - skip webhook signature validation
config = FlowChat::Whatsapp::Configuration.new
config.access_token = "test_token"
config.phone_number_id = "test_phone_id"
config.verify_token = "test_verify_token"
config.skip_signature_validation = Rails.env.test?  # Skip validation for testing

processor = FlowChat::Whatsapp::Processor.new(self) do |config|
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, custom_config
  config.use_session_store FlowChat::Session::CacheSessionStore
end
```

### Test Helper Methods

Useful helper methods for creating test data:

```ruby
private

def create_valid_webhook_payload(message_text = "Test message")
  {
    entry: [{
      changes: [{
        value: {
          messages: [{
            from: "1234567890",
            text: { body: message_text },
            type: "text",
            id: "wamid.test_#{SecureRandom.hex(8)}"
          }]
        }
      }]
    }]
  }
end

def generate_webhook_signature(payload_json, secret = @app_secret)
  OpenSSL::HMAC.hexdigest(
    OpenSSL::Digest.new("sha256"),
    secret,
    payload_json
  )
end

def generate_simulator_cookie(secret = FlowChat::Config.simulator_secret)
  timestamp = Time.now.to_i
  message = "simulator:#{timestamp}"
  signature = OpenSSL::HMAC.hexdigest(
    OpenSSL::Digest.new("sha256"), 
    secret, 
    message
  )
  "#{timestamp}:#{signature}"
end
```

### Testing Best Practices

**✅ DO:**
- Use simulator mode for most testing scenarios
- Test both valid and invalid webhook signatures
- Use environment-specific test configurations
- Create helper methods for common test data
- Test error scenarios and edge cases

**❌ DON'T:**
- Skip validation in production environments
- Hardcode secrets in test files
- Use production credentials in tests
- Forget to test security scenarios

**Environment Guidelines:**
- **Development/Test**: Use simulator mode with generated secrets
- **Staging**: Option to skip validation for easier testing
- **Production**: Always require full security validation

This comprehensive testing approach ensures your FlowChat application works correctly across all scenarios while maintaining security best practices.

## Configuration Reference

### Framework Configuration

```ruby
# config/initializers/flowchat.rb

# Core configuration
FlowChat::Config.logger = Rails.logger
FlowChat::Config.cache = Rails.cache
FlowChat::Config.simulator_secret = "your_secure_secret_here"

# USSD configuration
FlowChat::Config.ussd.pagination_page_size = 140
FlowChat::Config.ussd.pagination_next_option = "#"
FlowChat::Config.ussd.pagination_next_text = "More"
FlowChat::Config.ussd.pagination_back_option = "0"
FlowChat::Config.ussd.pagination_back_text = "Back"
FlowChat::Config.ussd.resumable_sessions_enabled = true
FlowChat::Config.ussd.resumable_sessions_timeout_seconds = 300

# WhatsApp configuration
FlowChat::Config.whatsapp.message_handling_mode = :inline  # :inline, :background, :simulator
FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
```

### WhatsApp Security Configuration

```ruby
# Per-configuration security settings
config = FlowChat::Whatsapp::Configuration.new
config.app_secret = "your_whatsapp_app_secret"          # Required for signature validation
config.skip_signature_validation = false                # Default: false (enforce validation)

# Security modes:
# 1. Full security (production)
config.app_secret = "secret"
config.skip_signature_validation = false

# 2. Development mode (disable validation)
config.app_secret = nil
config.skip_signature_validation = true
```

### Environment-Specific Configurations

```ruby
# config/initializers/flowchat.rb

case Rails.env
when 'development'
  FlowChat::Config.whatsapp.message_handling_mode = :simulator
  FlowChat::Config.simulator_secret = Rails.application.secret_key_base + "_dev"
  
when 'test'
  FlowChat::Config.whatsapp.message_handling_mode = :simulator
  FlowChat::Config.simulator_secret = "test_secret"
  
when 'staging'
  FlowChat::Config.whatsapp.message_handling_mode = :inline
  FlowChat::Config.simulator_secret = ENV['FLOWCHAT_SIMULATOR_SECRET']
  
when 'production'
  FlowChat::Config.whatsapp.message_handling_mode = :background
  FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
  FlowChat::Config.simulator_secret = ENV['FLOWCHAT_SIMULATOR_SECRET']
end
```

## Best Practices

### 1. Security Best Practices

**Production Security Checklist:**

✅ **Always configure app_secret** for webhook validation
```ruby
config.app_secret = "your_whatsapp_app_secret"  # Never leave empty in production
config.skip_signature_validation = false        # Never disable in production
```

✅ **Use secure simulator secrets**
```ruby
# Use Rails secret_key_base + suffix for uniqueness
FlowChat::Config.simulator_secret = Rails.application.secret_key_base + "_simulator"

# Or use environment variables
FlowChat::Config.simulator_secret = ENV['FLOWCHAT_SIMULATOR_SECRET']
```

✅ **Environment-specific configuration**
```ruby
# Different security levels per environment
if Rails.env.production?
  config.skip_signature_validation = false  # Enforce validation
else
  config.skip_signature_validation = true   # Allow for development
end
```

✅ **Enable simulator only when needed**
```ruby
# Only enable simulator in development/staging (default)
enable_simulator = Rails.env.development? || Rails.env.staging?
processor = FlowChat::Whatsapp::Processor.new(self, enable_simulator: enable_simulator)
```

### 5. Choose the Right WhatsApp Mode

Configure the appropriate mode based on your environment and requirements:

```ruby
# config/initializers/flowchat.rb

# Development/Testing - use simulator mode with security
if Rails.env.development? || Rails.env.test?
  FlowChat::Config.whatsapp.message_handling_mode = :simulator
  FlowChat::Config.simulator_secret = Rails.application.secret_key_base + "_dev"
end

# Staging - use inline mode with full security
if Rails.env.staging?
  FlowChat::Config.whatsapp.message_handling_mode = :inline
  FlowChat::Config.simulator_secret = ENV['FLOWCHAT_SIMULATOR_SECRET']
end

# Production - use background mode with full security
if Rails.env.production?
  FlowChat::Config.whatsapp.message_handling_mode = :background
  FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
  FlowChat::Config.simulator_secret = ENV['FLOWCHAT_SIMULATOR_SECRET']
end
```

### 6. Error Handling Best Practices

Handle security and configuration errors gracefully:

```ruby
def webhook
  begin
    processor = FlowChat::Whatsapp::Processor.new(self, enable_simulator: Rails.env.development?) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run WelcomeFlow, :main_page
    
  rescue FlowChat::Whatsapp::ConfigurationError => e
    Rails.logger.error "WhatsApp configuration error: #{e.message}"
    head :internal_server_error
    
  rescue => e
    Rails.logger.error "Unexpected error processing WhatsApp webhook: #{e.message}"
    head :internal_server_error
  end
end
```

## Appendix

### Context Variables Reference

FlowChat provides a rich set of context variables that are available throughout your flows. These variables are automatically populated based on the gateway and message type.

#### Core Context Variables

**Request Variables**

| Variable | Description |
|----------|-------------|
| `context.input` | Current user input |
| `context["request.id"]` | Unique request ID |
| `context["request.timestamp"]` | Request timestamp |
| `context["request.msisdn"]` | User's phone number |
| `context["request.gateway"]` | Current gateway (`:whatsapp_cloud_api`, `:ussd_nalo`) |
| `context["enable_simulator"]` | Whether simulator mode is enabled for this request |
| `context["simulator_mode"]` | Whether simulator mode is active |

**Flow Variables**

| Variable | Description |
|----------|-------------|
| `context["flow.name"]` | Current flow name |
| `context["flow.class"]` | Current flow class |
| `context["flow.action"]` | Current flow action/method |

**Session Variables**

| Variable | Description |
|----------|-------------|
| `context["session.id"]` | Current session ID |
| `context["session.store"]` | Session data store |

**Controller Variables**

| Variable | Description |
|----------|-------------|
| `context.controller` | Current controller instance |

#### WhatsApp-Specific Variables

| Variable | Description |
|----------|-------------|
| `context["whatsapp.message_result"]` | Result of last message send |
| `context["whatsapp.message_id"]` | WhatsApp message ID |
| `context["whatsapp.contact_name"]` | WhatsApp contact name |
| `context["whatsapp.location"]` | Location data if shared |
| `context["whatsapp.media"]` | Media data if attached |

#### USSD-Specific Variables

| Variable | Description |
|----------|-------------|
| `context["ussd.request"]` | Original USSD request |
| `context["ussd.response"]` | USSD response object |
| `context["ussd.pagination"]` | Pagination data for long messages |

#### Session Data Variables

| Variable | Description |
|----------|-------------|
| `context["$started_at$"]` | When the conversation started |

#### Usage Notes

1. **Access Methods:**
   ```ruby
   # Direct access
   context.input
   context["request.msisdn"]
   
   # Through app object in flows
   app.phone_number
   app.contact_name
   app.message_id
   ```

2. **Gateway-Specific Variables:**
   - WhatsApp variables are only available when using WhatsApp gateway
   - USSD variables are only available when using USSD gateway
   - Core variables are available across all gateways

3. **Session Persistence:**
   - Session data persists across requests
   - WhatsApp sessions expire after 7 days
   - USSD sessions expire after 1 hour
   - Default session TTL is 1 day

4. **Security:**
   - Webhook signatures are validated for WhatsApp requests
   - Simulator mode requires valid simulator cookie
   - Session data is encrypted at rest

5. **Flow Control:**
   - Context variables can be used to control flow logic
   - Session data can be used to maintain state
   - Request data can be used for validation