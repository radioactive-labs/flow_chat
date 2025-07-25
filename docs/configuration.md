# FlowChat Configuration

This guide covers all configuration options for FlowChat, from basic setup to advanced customization for production deployments.

## Global Configuration

Configure FlowChat globally in `config/initializers/flow_chat.rb`:

```ruby
# Basic configuration
FlowChat::Config.logger = Rails.logger
FlowChat::Config.cache = Rails.cache

# Validation behavior
FlowChat::Config.combine_validation_error_with_message = true

# Simulator settings (for development/testing)
FlowChat::Config.simulator_secret = "your_simulator_secret"
```

## Platform-Specific Configuration

### USSD Configuration

```ruby
# USSD pagination settings
FlowChat::Config.ussd.pagination_page_size = 160       # Characters per page
FlowChat::Config.ussd.pagination_next_option = "#"     # Next page option
FlowChat::Config.ussd.pagination_back_option = "0"     # Previous page option
FlowChat::Config.ussd.pagination_next_text = "More"    # Next page text
FlowChat::Config.ussd.pagination_back_text = "Back"    # Previous page text
```

### WhatsApp Configuration

```ruby
# WhatsApp API configuration
FlowChat::Config.whatsapp.api_base_url = "https://graph.facebook.com/v22.0"
```

### HTTP Configuration

```ruby
# HTTP gateway settings
FlowChat::Config.http.default_gateway = :simple
FlowChat::Config.http.request_timeout = 30
FlowChat::Config.http.response_format = :json
```

## Processor Configuration

Configure processors for each request:

```ruby
processor = FlowChat::Processor.new(self) do |config|
  # Gateway configuration
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  
  # Session configuration
  config.use_session_store FlowChat::Session::RailsSessionStore
  config.use_session_config(
    boundaries: [:flow, :platform, :gateway],
    identifier: :msisdn,
    hash_identifiers: true
  )
  
  # Middleware configuration
  config.use_middleware LoggingMiddleware
  config.use_middleware AuthenticationMiddleware
  
  # Convenience methods
  config.use_durable_sessions
  config.use_cross_platform_sessions
  config.use_url_isolation
end
```

## Session Configuration

### Session Boundaries

Control how session IDs are generated:

```ruby
# Available boundaries
boundaries: [
  :flow,      # Separate sessions per flow class
  :platform,  # Separate sessions per platform (ussd, whatsapp, http)
  :gateway,   # Separate sessions per gateway (nalo, cloud_api, etc.)
  :url        # Separate sessions per URL (multi-tenancy)
]

# Examples
config.use_session_config(boundaries: [:flow])                    # "survey_flow:user123"
config.use_session_config(boundaries: [:flow, :platform])         # "survey_flow:ussd:user123"
config.use_session_config(boundaries: [:flow, :url])              # "survey_flow:tenant1.app.com:user123"
```

### Session Identifiers

Choose what identifies a user session:

```ruby
# Identifier types
:request_id  # Ephemeral (new session each request)
:user_id     # Durable using user_id field
:msisdn      # Durable using phone number

# Examples
config.use_session_config(identifier: :request_id)  # Default for HTTP
config.use_session_config(identifier: :msisdn)      # Default for WhatsApp/USSD
config.use_session_config(identifier: :user_id)     # For authenticated users
```

### Session Stores

Choose where session data is stored:

```ruby
# Built-in session stores
config.use_session_store FlowChat::Session::RailsSessionStore    # Rails sessions
config.use_session_store FlowChat::Session::CacheSessionStore   # Rails cache

# Custom session store
config.use_session_store MyCompany::CustomSessionStore
```

### Convenience Methods

```ruby
# Durable sessions (use phone number, survive timeouts)
config.use_durable_sessions

# Cross-platform sessions (same user across USSD/WhatsApp)
config.use_cross_platform_sessions

# URL-based isolation (multi-tenancy)
config.use_url_isolation
```

## Gateway Configuration

### Built-in Gateways

#### USSD - Nalo Gateway

```ruby
config.use_gateway FlowChat::Ussd::Gateway::Nalo

# No additional configuration required for Nalo
```

#### WhatsApp - Cloud API Gateway

```ruby
# Basic configuration (uses Rails credentials)
config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi

# Custom configuration
whatsapp_config = FlowChat::Whatsapp::Configuration.new
whatsapp_config.access_token = ENV["WHATSAPP_ACCESS_TOKEN"]
whatsapp_config.phone_number_id = ENV["WHATSAPP_PHONE_NUMBER_ID"]
whatsapp_config.verify_token = ENV["WHATSAPP_VERIFY_TOKEN"]
whatsapp_config.app_secret = ENV["WHATSAPP_APP_SECRET"]
whatsapp_config.skip_signature_validation = Rails.env.development?

config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, whatsapp_config
```

#### HTTP - Simple Gateway

```ruby
config.use_gateway FlowChat::Http::Gateway::Simple

# No additional configuration required
```

### Custom Gateway Configuration

```ruby
# Custom gateway with configuration
my_config = MyCompany::CustomGatewayConfig.new
my_config.api_key = ENV["CUSTOM_API_KEY"]
my_config.endpoint = ENV["CUSTOM_ENDPOINT"]

config.use_gateway MyCompany::CustomGateway, my_config
```

## Environment-Specific Configuration

### Development Configuration

```ruby
# config/environments/development.rb
Rails.application.configure do
  # Enable detailed logging
  config.log_level = :debug
  
  # FlowChat development settings
  config.after_initialize do
    FlowChat::Config.logger = Rails.logger
    FlowChat::Config.logger.level = Logger::DEBUG
    
    # USSD settings for development
    FlowChat::Config.ussd.pagination_page_size = 200  # Larger for easier testing
    
    # WhatsApp settings for development
    FlowChat::Config.whatsapp.message_handling_mode = :inline
    
    # Enable simulator
    FlowChat::Config.simulator_secret = "dev_secret_123"
  end
end
```

### Production Configuration

```ruby
# config/environments/production.rb
Rails.application.configure do
  # Production logging
  config.log_level = :info
  
  # FlowChat production settings
  config.after_initialize do
    FlowChat::Config.logger = Rails.logger
    
    # USSD production settings
    FlowChat::Config.ussd.pagination_page_size = 140  # Conservative for compatibility
    
    # WhatsApp uses inline by default
    
    # Disable simulator in production
    FlowChat::Config.simulator_secret = nil
  end
end
```

### Staging Configuration

```ruby
# config/environments/staging.rb
Rails.application.configure do
  # Staging-specific settings
  config.after_initialize do
    FlowChat::Config.logger = Rails.logger
    FlowChat::Config.logger.level = Logger::DEBUG  # More verbose for staging
    
    # Use background processing but with shorter delays
    FlowChat::Config.whatsapp.message_handling_mode = :background
    
    # Enable simulator with staging secret
    FlowChat::Config.simulator_secret = ENV["STAGING_SIMULATOR_SECRET"]
  end
end
```

## Multi-Tenant Configuration

### URL-Based Tenancy

```ruby
class MultiTenantController < ApplicationController
  def process_request
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, tenant_whatsapp_config
      config.use_session_store FlowChat::Session::CacheSessionStore
      
      # Enable URL-based session isolation
      config.use_url_isolation
      
      # Optional: Additional tenant isolation
      config.use_session_config(
        boundaries: [:flow, :platform, :url],
        identifier: :user_id
      )
    end

    processor.run tenant_flow_class, :main_action
  end

  private

  def tenant_whatsapp_config
    tenant = extract_tenant_from_request
    tenant.whatsapp_configuration
  end

  def tenant_flow_class
    tenant = extract_tenant_from_request
    tenant.flow_class
  end

  def extract_tenant_from_request
    # Extract tenant from subdomain, domain, or path
    subdomain = request.subdomain
    Tenant.find_by(subdomain: subdomain)
  end
end
```

### Database-Based Tenancy

```ruby
class TenantSpecificController < ApplicationController
  before_action :set_tenant

  def process_request
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway gateway_for_tenant
      config.use_session_store FlowChat::Session::CacheSessionStore
      
      # Custom session boundaries for tenant isolation
      config.use_session_config(
        boundaries: [:flow, :platform],
        identifier: :user_id
      )
    end

    processor.run @tenant.flow_class.constantize, :main_action
  end

  private

  def set_tenant
    @tenant = Tenant.find(params[:tenant_id])
  end

  def gateway_for_tenant
    case @tenant.platform
    when 'whatsapp'
      FlowChat::Whatsapp::Gateway::CloudApi
    when 'ussd'
      FlowChat::Ussd::Gateway::Nalo
    else
      FlowChat::Http::Gateway::Simple
    end
  end
end
```

## Security Configuration

### WhatsApp Signature Validation

```ruby
# Always validate signatures in production
whatsapp_config = FlowChat::Whatsapp::Configuration.new
whatsapp_config.app_secret = ENV["WHATSAPP_APP_SECRET"]
whatsapp_config.skip_signature_validation = false  # Never skip in production

# Only skip validation in development if needed
whatsapp_config.skip_signature_validation = Rails.env.development?
```

### Session Security

```ruby
# Hash sensitive identifiers
config.use_session_config(
  identifier: :msisdn,
  hash_identifiers: true  # Phone numbers are hashed for privacy
)

# Implement custom session store with encryption
class EncryptedSessionStore < FlowChat::Session::CacheSessionStore
  def set(key, value)
    encrypted_value = encrypt(value.to_json)
    super(key, encrypted_value)
  end

  def get(key)
    encrypted_value = super(key)
    return nil unless encrypted_value
    
    decrypted = decrypt(encrypted_value)
    JSON.parse(decrypted)
  rescue
    nil  # Return nil if decryption fails
  end

  private

  def encrypt(data)
    # Use Rails credentials or environment variable
    secret = Rails.application.credentials.session_encryption_key
    crypt = ActiveSupport::MessageEncryptor.new(secret)
    crypt.encrypt_and_sign(data)
  end

  def decrypt(encrypted_data)
    secret = Rails.application.credentials.session_encryption_key
    crypt = ActiveSupport::MessageEncryptor.new(secret)
    crypt.decrypt_and_verify(encrypted_data)
  end
end

# Use encrypted session store
config.use_session_store EncryptedSessionStore
```

## Performance Configuration

### Redis Cache Configuration

```ruby
# config/initializers/redis.rb
redis_config = {
  url: ENV["REDIS_URL"],
  pool_size: ENV.fetch("REDIS_POOL_SIZE", 5).to_i,
  pool_timeout: ENV.fetch("REDIS_POOL_TIMEOUT", 5).to_i
}

# Use Redis for session storage
Rails.application.configure do
  config.cache_store = :redis_cache_store, redis_config
end

# FlowChat will automatically use Rails.cache
FlowChat::Config.cache = Rails.cache
```

### Background Job Configuration

```ruby
# config/initializers/sidekiq.rb (if using Sidekiq)
Sidekiq.configure_server do |config|
  config.redis = { url: ENV["REDIS_URL"] }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV["REDIS_URL"] }
end

# WhatsApp uses inline responses by defaul
```

### Database Connection Configuration

```ruby
# config/database.yml
production:
  adapter: postgresql
  pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5) %>
  timeout: 5000
  # ... other database settings
  
  # For high-volume USSD applications
  checkout_timeout: 2
  reaping_frequency: 10
```

## Monitoring Configuration

### Instrumentation Setup

```ruby
# config/initializers/flow_chat.rb
FlowChat.setup_instrumentation!

# Subscribe to FlowChat events
ActiveSupport::Notifications.subscribe("flow_chat.message_received") do |event|
  # Log message received
  Rails.logger.info "Message received: #{event.payload}"
end

ActiveSupport::Notifications.subscribe("flow_chat.message_sent") do |event|
  # Log message sent
  Rails.logger.info "Message sent: #{event.payload}"
end

ActiveSupport::Notifications.subscribe("flow_chat.flow_execution_error") do |event|
  # Alert on flow errors
  ErrorNotificationService.notify(event.payload)
end
```

### Custom Metrics

```ruby
# Custom metrics collector
class CustomMetricsCollector
  def self.collect_metrics
    {
      active_sessions: count_active_sessions,
      messages_per_minute: calculate_message_rate,
      error_rate: calculate_error_rate
    }
  end

  private

  def self.count_active_sessions
    # Implementation depends on your session store
    Rails.cache.redis.keys("flow_chat:session:*").count
  end

  def self.calculate_message_rate
    # Implementation depends on your metrics storage
    # Return messages processed in the last minute
  end

  def self.calculate_error_rate
    # Calculate error percentage
  end
end

# Setup metrics collection
FlowChat::Config.metrics_collector = CustomMetricsCollector
```

## Testing Configuration

### Test Environment

```ruby
# config/environments/test.rb
Rails.application.configure do
  config.after_initialize do
    FlowChat::Config.logger = Rails.logger
    FlowChat::Config.logger.level = Logger::ERROR  # Reduce noise in tests
    
    # Use memory cache for tests
    FlowChat::Config.cache = ActiveSupport::Cache::MemoryStore.new
    
    # Disable background processing in tests
    FlowChat::Config.whatsapp.message_handling_mode = :inline
    
    # Enable simulator for testing
    FlowChat::Config.simulator_secret = "test_secret"
  end
end
```

### Test Helper Configuration

```ruby
# test/test_helper.rb
class ActiveSupport::TestCase
  def setup_flow_chat_test_environment
    # Reset FlowChat state between tests
    FlowChat::Config.cache.clear
    
    # Mock external API calls
    stub_whatsapp_api_calls
    stub_ussd_gateway_calls
  end

  def create_test_processor(platform: :ussd, **options)
    gateway_class = case platform
    when :ussd then FlowChat::Ussd::Gateway::Nalo
    when :whatsapp then FlowChat::Whatsapp::Gateway::CloudApi
    when :http then FlowChat::Http::Gateway::Simple
    end

    FlowChat::Processor.new(MockController.new) do |config|
      config.use_gateway gateway_class
      config.use_session_store FlowChat::Session::MemorySessionStore
      options.each { |key, value| config.send(key, value) }
    end
  end
end
```

## Troubleshooting Configuration

### Debug Mode

```ruby
# Enable comprehensive debugging
FlowChat::Config.logger.level = Logger::DEBUG

# Add custom debug middleware
class DebugMiddleware
  def initialize(app)
    @app = app
  end

  def call(context)
    Rails.logger.debug "=== FlowChat Debug ==="
    Rails.logger.debug "Context: #{context.to_h}"
    Rails.logger.debug "Input: #{context.input.inspect}"
    Rails.logger.debug "Session ID: #{context['session.id']}"
    
    result = @app.call(context)
    
    Rails.logger.debug "Result: #{result.inspect}"
    Rails.logger.debug "======================"
    
    result
  end
end

# Use debug middleware
config.use_middleware DebugMiddleware
```

### Configuration Validation

```ruby
# Add configuration validation
class ConfigurationValidator
  def self.validate!
    validate_environment_variables!
    validate_gateway_configuration!
    validate_session_configuration!
  end

  private

  def self.validate_environment_variables!
    required_vars = %w[
      WHATSAPP_ACCESS_TOKEN
      WHATSAPP_PHONE_NUMBER_ID
      WHATSAPP_VERIFY_TOKEN
    ]

    missing = required_vars.select { |var| ENV[var].blank? }
    raise "Missing environment variables: #{missing.join(', ')}" if missing.any?
  end

  def self.validate_gateway_configuration!
    # Validate gateway-specific configuration
  end

  def self.validate_session_configuration!
    # Validate session store connectivity
    FlowChat::Config.cache.write("test_key", "test_value")
    FlowChat::Config.cache.delete("test_key")
  rescue => e
    raise "Session store configuration invalid: #{e.message}"
  end
end

# Run validation on startup
Rails.application.config.after_initialize do
  ConfigurationValidator.validate! if Rails.env.production?
end
```

This configuration guide covers all aspects of FlowChat setup. For platform-specific configuration details, see the individual platform guides. 