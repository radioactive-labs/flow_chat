# Configuration Reference

This document covers all FlowChat configuration options.

## Framework Configuration

```ruby
# config/initializers/flowchat.rb

# Core configuration
FlowChat::Config.logger = Rails.logger
FlowChat::Config.cache = Rails.cache
FlowChat::Config.simulator_secret = "your_secure_secret_here"

# Validation error display behavior
FlowChat::Config.combine_validation_error_with_message = true  # default

# Setup instrumentation (optional)
FlowChat.setup_instrumentation!
```

## USSD Configuration

```ruby
# USSD pagination settings
FlowChat::Config.ussd.pagination_page_size = 140          # characters per page
FlowChat::Config.ussd.pagination_next_option = "#"        # option to go to next page
FlowChat::Config.ussd.pagination_next_text = "More"       # text for next option
FlowChat::Config.ussd.pagination_back_option = "0"        # option to go back
FlowChat::Config.ussd.pagination_back_text = "Back"       # text for back option

# Resumable sessions
FlowChat::Config.ussd.resumable_sessions_enabled = true   # default
FlowChat::Config.ussd.resumable_sessions_timeout_seconds = 300  # 5 minutes
```

## WhatsApp Configuration

```ruby
# Message handling modes
FlowChat::Config.whatsapp.message_handling_mode = :inline  # :inline, :background, :simulator
FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
```

### WhatsApp Credential Configuration

#### Option 1: Rails Credentials

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
  skip_signature_validation: false
```

#### Option 2: Environment Variables

```bash
export WHATSAPP_ACCESS_TOKEN="your_access_token"
export WHATSAPP_PHONE_NUMBER_ID="your_phone_number_id" 
export WHATSAPP_VERIFY_TOKEN="your_verify_token"
export WHATSAPP_APP_ID="your_app_id"
export WHATSAPP_APP_SECRET="your_app_secret"
export WHATSAPP_BUSINESS_ACCOUNT_ID="your_business_account_id"
export WHATSAPP_SKIP_SIGNATURE_VALIDATION="false"
```

#### Option 3: Programmatic Configuration

```ruby
config = FlowChat::Whatsapp::Configuration.new(:my_config)  # Named configuration
config.access_token = "your_access_token"
config.phone_number_id = "your_phone_number_id"
config.verify_token = "your_verify_token"
config.app_id = "your_app_id"
config.app_secret = "your_app_secret"
config.business_account_id = "your_business_account_id"
config.skip_signature_validation = false
# Configuration is automatically registered as :my_config
```

**⚠️ Important for Background Jobs:** When using background mode with programmatic configurations, you must register them in an initializer:

```ruby
# config/initializers/whatsapp_configs.rb
# Register configurations so background jobs can access them
production_config = FlowChat::Whatsapp::Configuration.new(:production)
production_config.access_token = ENV['PROD_WHATSAPP_TOKEN']
# ... other settings

staging_config = FlowChat::Whatsapp::Configuration.new(:staging)  
staging_config.access_token = ENV['STAGING_WHATSAPP_TOKEN']
# ... other settings
```

Then use named configurations in controllers:

```ruby
# Use registered configuration
config = FlowChat::Whatsapp::Configuration.get(:production)
processor = FlowChat::Whatsapp::Processor.new(self) do |config|
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, config
end
```

## Security Configuration

### WhatsApp Security

```ruby
# Production security (recommended)
config.app_secret = "your_whatsapp_app_secret"
config.skip_signature_validation = false  # default

# Development mode (disable validation)
config.app_secret = nil
config.skip_signature_validation = true
```

### Simulator Security

```ruby
# Use Rails secret for uniqueness
FlowChat::Config.simulator_secret = Rails.application.secret_key_base + "_simulator"

# Or use dedicated secret
FlowChat::Config.simulator_secret = ENV['FLOWCHAT_SIMULATOR_SECRET']
```

## Environment-Specific Configuration

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

## Processor Configuration

### USSD Processor

```ruby
processor = FlowChat::Ussd::Processor.new(self) do |config|
  # Gateway (required)
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  
  # Session storage (required)
  config.use_session_store FlowChat::Session::CacheSessionStore
  
  # Optional middleware
  config.use_middleware MyCustomMiddleware
  
  # Optional resumable sessions
  config.use_resumable_sessions
end
```

### WhatsApp Processor

```ruby
processor = FlowChat::Whatsapp::Processor.new(self, enable_simulator: Rails.env.development?) do |config|
  # Gateway (required)
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
  
  # Session storage (required)  
  config.use_session_store FlowChat::Session::CacheSessionStore
  
  # Optional custom configuration
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, custom_whatsapp_config
end
```

## Session Store Options

### Cache Session Store

```ruby
config.use_session_store FlowChat::Session::CacheSessionStore
```

Uses Rails cache backend with automatic TTL management. This is the primary session store available in FlowChat.

## Middleware Configuration

### Built-in Middleware

```ruby
# Pagination (USSD only, automatic)
FlowChat::Ussd::Middleware::Pagination

# Session management (automatic)
FlowChat::Session::Middleware

# Gateway communication (automatic)
FlowChat::Ussd::Gateway::Nalo
FlowChat::Whatsapp::Gateway::CloudApi
```

### Custom Middleware

```ruby
class LoggingMiddleware
  def initialize(app)
    @app = app
  end

  def call(context)
    Rails.logger.info "Processing request: #{context.input}"
    result = @app.call(context)
    Rails.logger.info "Response: #{result[1]}"
    result
  end
end

# Use custom middleware
config.use_middleware LoggingMiddleware
```

## Validation Configuration

### Error Display Options

```ruby
# Combine validation error with original message (default)
FlowChat::Config.combine_validation_error_with_message = true
# User sees: "Invalid email format\n\nEnter your email:"

# Show only validation error
FlowChat::Config.combine_validation_error_with_message = false
# User sees: "Invalid email format"
```

## Background Job Configuration

### Job Class Setup

```ruby
# app/jobs/whatsapp_message_job.rb
class WhatsappMessageJob < ApplicationJob
  include FlowChat::Whatsapp::SendJobSupport

  def perform(send_data)
    perform_whatsapp_send(send_data)
  end
end
```

**Configuration Resolution:** The job automatically resolves configurations using:
1. Named configuration from `send_data[:configuration_name]` if present
2. Default configuration from credentials/environment variables

For custom resolution logic, override the configuration resolution:

```ruby
class CustomWhatsappMessageJob < ApplicationJob
  include FlowChat::Whatsapp::SendJobSupport

  def perform(send_data)
    perform_whatsapp_send(send_data)
  end

  private

  def resolve_whatsapp_configuration(send_data)
    # Custom logic to resolve configuration
    tenant_id = ...
    FlowChat::Whatsapp::Configuration.get("tenant_#{tenant_id}")
  end
end
```

### Queue Configuration

```ruby
# config/application.rb
config.active_job.queue_adapter = :sidekiq

# config/initializers/flowchat.rb
FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
```

## Instrumentation Configuration

### Basic Setup

```ruby
# Enable instrumentation
FlowChat.setup_instrumentation!
```

### Custom Event Subscribers

```ruby
# Subscribe to specific events
ActiveSupport::Notifications.subscribe("flow.execution.end.flow_chat") do |event|
  # Custom handling
  ExternalMonitoring.track_flow_execution(
    event.payload[:flow_name], 
    event.duration
  )
end

# Subscribe to all FlowChat events
ActiveSupport::Notifications.subscribe(/\.flow_chat$/) do |name, start, finish, id, payload|
  CustomLogger.log_event(name, payload.merge(duration: finish - start))
end
```

## Configuration Validation

FlowChat validates configuration at runtime and provides helpful error messages:

FlowChat validates configuration at runtime and provides helpful error messages for missing or invalid configurations. 