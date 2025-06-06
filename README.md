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
- 📊 **Built-in Instrumentation** - Comprehensive monitoring, metrics, and logging with zero configuration
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
      config.use_session_store FlowChat::Session::CacheSessionStore
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

FlowChat provides a powerful built-in simulator for testing flows in both USSD and WhatsApp modes. The simulator allows you to test different endpoints on your local server without needing actual USSD or WhatsApp infrastructure.

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
      ussd: {
        name: "USSD Integration",
        icon: "📱",
        processor_type: "ussd",
        provider: "nalo",
        endpoint: "/ussd",
        color: "#007bff"
      },
      whatsapp: {
        name: "WhatsApp Integration", 
        icon: "💬",
        processor_type: "whatsapp",
        provider: "cloud_api",
        endpoint: "/whatsapp/webhook",
        color: "#25D366"
      },
      alternative_whatsapp: {
        name: "Alternative WhatsApp Endpoint",
        icon: "🔄",
        processor_type: "whatsapp", 
        provider: "cloud_api",
        endpoint: "/alternative_whatsapp/webhook",
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
- 🔄 **Endpoint Toggle** - Switch between different integration endpoints
- 📱 **USSD Mode** - Classic terminal simulation with pagination
- 💬 **WhatsApp Mode** - Full WhatsApp interface with interactive elements
- 🎨 **Modern UI** - Beautiful, responsive interface
- 📊 **Request Logging** - View HTTP requests and responses in real-time
- 🔧 **Developer Tools** - Character counts, connection status, error handling
- 🔒 **Secure Authentication** - HMAC-signed cookies with expiration

Visit `http://localhost:3000/simulator` to access the simulator interface and test your local endpoints.

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

FlowChat provides a unified API that works across both USSD and WhatsApp platforms, with graceful degradation for platform-specific features. Under the hood, FlowChat uses a unified prompt architecture that ensures consistent behavior across platforms while optimizing the user experience for each channel.

### Shared Features (Both USSD & WhatsApp)
- ✅ `app.screen()` - Interactive screens with prompts
- ✅ `app.say()` - Send messages to users  
- ✅ `prompt.ask()` - Flexible text input with optional validation and choices as suggestions
- ✅ `prompt.select()` - Forced selection from predefined options (numbered lists in USSD, interactive buttons in WhatsApp)
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
        validate: ->(input) { "Must be 18 or older" unless input.to_i >= 18 },
        transform: ->(input) { input.to_i },
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
    # Validate the raw input first
    validate: ->(input) { 
      "Invalid email format" unless input.strip.downcase.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
    },
    
    # Transform input after validation passes
    transform: ->(input) { input.strip.downcase }
end
```

### Prompt Methods: `ask` vs `select`

FlowChat provides two distinct methods for collecting user input, each designed for different use cases:

#### `prompt.ask()` - Flexible Input Collection

Use `ask()` when you want to collect **flexible user input** with optional validation and transformation. The user can type anything, and you can optionally provide choices as **suggestions** to guide them.

```ruby
# Free-form text input
name = app.screen(:name) do |prompt|
  prompt.ask "What's your name?",
    transform: ->(input) { input.strip.titleize }
end

# Input with validation but no restrictions
email = app.screen(:email) do |prompt|
  prompt.ask "Enter your email address:",
    validate: ->(input) { "Invalid email format" unless input.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i) }
end

# Suggestions with flexible validation
color = app.screen(:color) do |prompt|
  prompt.ask "What's your favorite color?",
    choices: {"red" => "Red", "blue" => "Blue", "green" => "Green"},  # Optional suggestions
    validate: ->(input) { "Please enter a valid color" unless %w[red blue green yellow purple].include?(input.downcase) }
end
# User can type "red", "blue", "purple", "yellow" - not limited to suggestions
```

**Key characteristics of `ask()`:**
- ✅ **Flexible input** - Users can type anything
- ✅ **Optional choices** - Choices are suggestions, not restrictions
- ✅ **Custom validation** - You define what's valid
- ✅ **Returns raw input** - Exactly what the user typed as string (possibly transformed)

#### `prompt.select()` - Forced Choice Selection

Use `select()` when you want to **force users to pick from predefined options**. This ensures users can only select valid choices and provides automatic validation.

```ruby
# Array choices - users select by position (1, 2, 3 for USSD)
language = app.screen(:language) do |prompt|
  prompt.select "Choose your language:", ["English", "French", "Spanish"]
end
# Returns: "English", "French", or "Spanish"

# Hash choices - users select by key, get key back
plan = app.screen(:plan) do |prompt|
  prompt.select "Choose a plan:", {
    "basic" => "Basic Plan ($10/month)",
    "premium" => "Premium Plan ($25/month)", 
    "enterprise" => "Enterprise Plan ($100/month)"
  }
end
# User sees "Basic Plan ($10/month)" etc but you get back: "basic", "premium", or "enterprise"

# Forced yes/no decision
confirmed = app.screen(:confirm) do |prompt|
  prompt.select "Proceed with payment?", ["Yes", "No"]
end
# Returns: "Yes" or "No"
```

**Key characteristics of `select()`:**
- ✅ **Restricted input** - Users must pick from provided options
- ✅ **Automatic validation** - No invalid choices possible
- ✅ **Platform optimization** - Numbers for USSD, buttons for WhatsApp
- ✅ **Returns choice value** - Array item or hash key (the array value/hash type is preserved)

#### Platform-Specific Behavior

**USSD Experience:**
```ruby
prompt.select "Choose color:", ["Red", "Blue", "Green"]
```
**Displays:**
```
Choose color:
1. Red
2. Blue  
3. Green
```
**User types:** `2` **→ Returns:** `"Blue"`

**WhatsApp Experience:**
- Interactive buttons or list messages
- User taps choice directly
- Same return values as USSD

#### When to Use Which?

| Use `ask()` when: | Use `select()` when: |
|------------------|---------------------|
| ✅ Collecting names, emails, descriptions | ✅ Choosing from fixed options |
| ✅ Numeric input with validation | ✅ Navigation menus |
| ✅ You want to allow "other" responses | ✅ Yes/no decisions |
| ✅ Flexible user expression needed | ✅ Ensuring data consistency |

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
    quantity = app.screen(:quantity) { |p| p.ask "Quantity:", transform: ->(input) { input.to_i } }
    
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

### Validation Error Display

Configure how validation errors are displayed to users:

```ruby
# config/initializers/flowchat.rb

# Default behavior: combine error with original message
FlowChat::Config.combine_validation_error_with_message = true
# User sees: "Card number must be 16 digits\n\nEnter credit card number:"

# Show only the error message
FlowChat::Config.combine_validation_error_with_message = false  
# User sees: "Card number must be 16 digits"
```

**Use cases for each approach:**

- **Combined (default)**: Better for first-time users who need context about what they're entering
- **Error only**: Cleaner UX for experienced users, reduces message length for USSD character limits

**Example with both approaches:**

```ruby
# This validation code works the same way regardless of config
age = app.screen(:age) do |prompt|
  prompt.ask "How old are you?",
    validate: ->(input) { "You must be at least 18 years old" unless input.to_i >= 18 },
    transform: ->(input) { input.to_i },
end

# With combine_validation_error_with_message = true (default):
# "You must be at least 18 years old
# 
# How old are you?"

# With combine_validation_error_with_message = false:
# "You must be at least 18 years old"
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
  config.use_session_store FlowChat::Session::CacheSessionStore
  
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
  config.use_session_store FlowChat::Session::CacheSessionStore
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
  config.use_session_store FlowChat::Session::CacheSessionStore
  config.use_middleware LoggingMiddleware
end
```

### Multiple Gateways

FlowChat supports multiple USSD gateways:

```ruby
# Nalo Solutions Gateway
config.use_gateway FlowChat::Ussd::Gateway::Nalo
```

## Instrumentation & Monitoring

FlowChat includes an instrumentation system that provides observability, monitoring, and logging for your conversational applications. The instrumentation system tracks flow executions, session management, gateway interactions, and performance metrics.

### Quick Setup

Enable instrumentation in your Rails application:

```ruby
# config/initializers/flowchat.rb
FlowChat.setup_instrumentation!
```

This single line sets up:
- 📊 **Metrics Collection** - Performance and usage metrics
- 📝 **Structured Logging** - Event-driven logs with context
- 🔍 **Event Tracking** - All framework events instrumented
- ⚡ **Performance Monitoring** - Execution timing and bottleneck detection

### Features

**🎯 Zero Configuration**
- Works out of the box with Rails applications
- Automatic ActiveSupport::Notifications integration
- Thread-safe metrics collection

**📈 Comprehensive Metrics**
- Flow execution counts and timing
- Session creation/destruction rates
- WhatsApp/USSD message volumes
- Cache hit/miss ratios
- Error tracking by type and flow

**🔍 Rich Event Tracking**
- 20+ predefined event types
- Automatic context enrichment (session ID, flow name, gateway)
- Structured event payloads

**📊 Production Ready**
- Minimal performance overhead
- Thread-safe operations
- Graceful error handling

### Event Types

FlowChat instruments these key events:

**Flow Events**
```ruby
# Flow execution lifecycle
FlowChat::Instrumentation::Events::FLOW_EXECUTION_START
FlowChat::Instrumentation::Events::FLOW_EXECUTION_END  
FlowChat::Instrumentation::Events::FLOW_EXECUTION_ERROR
```

**Session Events**
```ruby
# Session management
FlowChat::Instrumentation::Events::SESSION_CREATED
FlowChat::Instrumentation::Events::SESSION_DESTROYED
FlowChat::Instrumentation::Events::SESSION_DATA_GET
FlowChat::Instrumentation::Events::SESSION_DATA_SET
FlowChat::Instrumentation::Events::SESSION_CACHE_HIT
FlowChat::Instrumentation::Events::SESSION_CACHE_MISS
```

**WhatsApp Events**
```ruby
# WhatsApp messaging
FlowChat::Instrumentation::Events::WHATSAPP_MESSAGE_RECEIVED
FlowChat::Instrumentation::Events::WHATSAPP_MESSAGE_SENT
FlowChat::Instrumentation::Events::WHATSAPP_WEBHOOK_VERIFIED
FlowChat::Instrumentation::Events::WHATSAPP_API_REQUEST
FlowChat::Instrumentation::Events::WHATSAPP_MEDIA_UPLOAD
```

**USSD Events**
```ruby
# USSD messaging
FlowChat::Instrumentation::Events::USSD_MESSAGE_RECEIVED
FlowChat::Instrumentation::Events::USSD_MESSAGE_SENT
FlowChat::Instrumentation::Events::USSD_PAGINATION_TRIGGERED
```

### Usage Examples

**Access Metrics**
```ruby
# Get current metrics snapshot
metrics = FlowChat.metrics.snapshot

# Flow execution metrics
flow_metrics = FlowChat.metrics.get_category("flows")
puts flow_metrics["flows.executed"] # Total flows executed
puts flow_metrics["flows.execution_time"] # Average execution time

# Session metrics  
session_metrics = FlowChat.metrics.get_category("sessions")
puts session_metrics["sessions.created"] # Total sessions created
puts session_metrics["sessions.cache.hits"] # Cache hit count
```

**Custom Instrumentation in Flows**
```ruby
class PaymentFlow < FlowChat::Flow
  def process_payment
    # Instrument custom events in your flows
    instrument("payment.started", {
      amount: payment_amount,
      currency: "USD",
      payment_method: "mobile_money"
    }) do
      # Payment processing logic
      result = process_mobile_money_payment
      
      # Event automatically includes session_id, flow_name, gateway
      result
    end
  end
end
```

**Custom Event Subscribers**
```ruby
# config/initializers/flowchat_instrumentation.rb
FlowChat.setup_instrumentation!

# Subscribe to specific events
ActiveSupport::Notifications.subscribe("flow.execution.end.flow_chat") do |event|
  # Custom handling for flow completion
  duration = event.duration
  flow_name = event.payload[:flow_name]
  
  # Send to external monitoring service
  ExternalMonitoring.track_flow_execution(flow_name, duration)
end

# Subscribe to all FlowChat events
ActiveSupport::Notifications.subscribe(/\.flow_chat$/) do |name, start, finish, id, payload|
  # Log all FlowChat events to external service
  CustomLogger.log_event(name, payload.merge(duration: finish - start))
end
```

**Integration with Rails Logging**
```ruby
# The instrumentation system automatically enhances Rails logs
# Example log output:

# [INFO] FlowChat Flow Execution Started: WelcomeFlow#main_page (session: abc123, gateway: whatsapp_cloud_api)
# [INFO] FlowChat WhatsApp Message Sent: to=+1234567890, type=text, length=45 (2.3ms)
# [INFO] FlowChat Flow Execution Completed: WelcomeFlow#main_page in 12.4ms (session: abc123)
# [ERROR] FlowChat Flow Execution Failed: PaymentFlow#process_payment - ArgumentError: Invalid amount (session: def456)
```

**Monitoring Dashboard Integration**
```ruby
# config/initializers/flowchat_monitoring.rb
FlowChat.setup_instrumentation!

# Export metrics to Prometheus, StatsD, etc.
ActiveSupport::Notifications.subscribe("flow.execution.end.flow_chat") do |event|
  StatsD.increment("flowchat.flows.executed")
  StatsD.timing("flowchat.flows.duration", event.duration)
  StatsD.increment("flowchat.flows.#{event.payload[:flow_name]}.executed")
end

# Track error rates
ActiveSupport::Notifications.subscribe("flow.execution.error.flow_chat") do |event|
  StatsD.increment("flowchat.flows.errors")
  StatsD.increment("flowchat.flows.errors.#{event.payload[:error_class]}")
end
```

### Performance Impact

The instrumentation system is designed for production use with minimal overhead:

- **Event Publishing**: ~0.1ms per event
- **Metrics Collection**: Thread-safe atomic operations
- **Memory Usage**: <1MB for typical applications
- **Storage**: Events are ephemeral, metrics are kept in memory

### Debugging & Troubleshooting

**Enable Debug Logging**
```ruby
# config/environments/development.rb
config.log_level = :debug

# Shows detailed instrumentation events:
# [DEBUG] FlowChat Event: session.data.get.flow_chat (payload: {key: "user_name", session_id: "abc123"})
```

**Reset Metrics**
```ruby
# Clear all metrics (useful for testing)
FlowChat.metrics.reset!
```

**Check Event Subscribers**
```ruby
# See all active subscribers
ActiveSupport::Notifications.notifier.listeners_for("flow.execution.end.flow_chat")
```

### Testing Instrumentation

FlowChat's instrumentation system includes comprehensive testing support:

```ruby
# test/test_helper.rb
class ActiveSupport::TestCase
  setup do
    # Reset metrics before each test
    FlowChat::Instrumentation::Setup.reset! if FlowChat::Instrumentation::Setup.setup?
  end
end

# In your tests
class FlowInstrumentationTest < ActiveSupport::TestCase
  test "flow execution is instrumented" do
    events = []
    
    # Capture events
    ActiveSupport::Notifications.subscribe(/flow_chat$/) do |name, start, finish, id, payload|
      events << { name: name, payload: payload, duration: (finish - start) * 1000 }
    end
    
    # Execute flow
    processor.run(WelcomeFlow, :main_page)
    
    # Verify events
    assert_equal 2, events.size
    assert_equal "flow.execution.start.flow_chat", events[0][:name]
    assert_equal "flow.execution.end.flow_chat", events[1][:name]
    assert_equal "welcome_flow", events[0][:payload][:flow_name]
  end
end
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
when 'development'
  # Enable simulator mode for testing
  FlowChat::Config.whatsapp.message_handling_mode = :simulator
  FlowChat::Config.simulator_secret = Rails.application.secret_key_base + "_dev"
  
when 'test'
  # Enable simulator mode for automated testing
  FlowChat::Config.whatsapp.message_handling_mode = :simulator
  FlowChat::Config.simulator_secret = "test_secret"
  
when 'staging'
  # Use inline mode but allow simulator for testing
  FlowChat::Config.whatsapp.message_handling_mode = :inline
  FlowChat::Config.simulator_secret = ENV['FLOWCHAT_SIMULATOR_SECRET']
  
when 'production'
  # Background processing in production, no simulator
  FlowChat::Config.whatsapp.message_handling_mode = :background
  FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
  FlowChat::Config.simulator_secret = nil
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
end
```

### Integration Testing

#### Simulator Mode Testing

```ruby
test "complete flow via simulator" do
  # Generate valid simulator cookie for authentication
  valid_cookie = generate_simulator_cookie
  
  webhook_payload = {
    entry: [{ changes: [{ value: { messages: [{ from: "1234567890", text: { body: "Hello" }, type: "text" }] } }] }],
    simulator_mode: true
  }

  post "/whatsapp/webhook", params: webhook_payload, cookies: { flowchat_simulator: valid_cookie }
  assert_response :success
end
```

#### Testing with Skipped Validation

```ruby
test "webhook processing with skipped validation" do
  config = FlowChat::Whatsapp::Configuration.new
  config.skip_signature_validation = true  # Skip for testing
  
  # No signature required when validation is skipped
  post "/whatsapp/webhook", params: webhook_payload.to_json
  assert_response :success
end
```

### Test Helper Methods

```ruby
private

def generate_webhook_signature(payload_json, secret = @app_secret)
  OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, payload_json)
end

def generate_simulator_cookie(secret = FlowChat::Config.simulator_secret)
  timestamp = Time.now.to_i
  message = "simulator:#{timestamp}"
  signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, message)
  "#{timestamp}:#{signature}"
end
```

## Configuration Reference

### Framework Configuration

```ruby
# config/initializers/flowchat.rb

# Core configuration
FlowChat::Config.logger = Rails.logger
FlowChat::Config.cache = Rails.cache
FlowChat::Config.simulator_secret = "your_secure_secret_here"

# Validation error display behavior
# When true (default), validation errors are combined with the original message.
# When false, only the validation error message is shown to the user.
FlowChat::Config.combine_validation_error_with_message = true

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

### 2. Flow Interaction Best Practices

**⚠️ Important: Flow Methods Must Always Interact With Users**

Every flow method execution **must** result in user interaction. FlowChat expects each request to either:

✅ **Prompt the user** (using `app.screen`, `prompt.ask`, `prompt.select`, etc.)
```ruby
# ✅ GOOD: Always results in user interaction
def main_page
  name = app.screen(:name) do |prompt|
    prompt.ask "What's your name?"
  end
  
  app.say "Hello, #{name}!"  # This terminates with a message
end
```

✅ **Terminate with a message** (using `app.say`)
```ruby
# ✅ GOOD: Terminates with user feedback
def complete_registration
  User.create(name: app.session.get(:name))
  app.say "Registration complete!"
end
```

❌ **Never leave methods without interaction**
```ruby
# ❌ BAD: Flow ends without user interaction
def main_page
  choice = app.screen(:menu) { |p| p.select "Choose:", ["A", "B"] }
  
  case choice
  when "option_a"
    handle_option_a  # If this doesn't interact with user
  when "option_b" 
    handle_option_b  # If this doesn't interact with user
  end
  # Missing interaction - will cause "Unexpected end of flow" error
end
```

**Platform-Specific Behavior:**
- **USSD**: Shows "Unexpected end of flow" error and terminates session
- **WhatsApp**: Silently completes (more permissive)

**Common Fixes:**
```ruby
# ✅ Add explicit termination
case choice
when "option_a"
  handle_option_a
  app.say "Option A completed!"
when "option_b"
  handle_option_b  
  app.say "Option B completed!"
else
  app.say "Invalid choice, please try again."
end

# ✅ Or ensure all called methods interact with user
def handle_option_a
  # Process data...
  app.say "Processing complete!"  # Always end with interaction
end
```

### 3. Choose the Right WhatsApp Mode

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

### 4. Error Handling Best Practices

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