# Example FlowChat Initializer
# Add this to your Rails application as config/initializers/flow_chat.rb

# Configure cache for session storage
# This is required when using FlowChat::Session::CacheSessionStore
FlowChat::Config.cache = Rails.cache

# Alternative cache configurations:

# Use a specific cache store
# FlowChat::Config.cache = ActiveSupport::Cache::MemoryStore.new

# Use Redis (requires redis gem)
# FlowChat::Config.cache = ActiveSupport::Cache::RedisCacheStore.new(url: "redis://localhost:6379/1")

# Use Memcached (requires dalli gem)
# FlowChat::Config.cache = ActiveSupport::Cache::MemCacheStore.new("localhost:11211")

# Configure logger (optional)
FlowChat::Config.logger = Rails.logger

# Configure simulator security (REQUIRED for simulator mode)
# This secret is used to authenticate simulator requests via signed cookies
case Rails.env
when 'development', 'test'
  # Use Rails secret key with environment suffix for development
  FlowChat::Config.simulator_secret = Rails.application.secret_key_base + "_#{Rails.env}"
when 'staging', 'production'
  # Use environment variable for production security
  FlowChat::Config.simulator_secret = ENV['FLOWCHAT_SIMULATOR_SECRET']
  
  # Fail fast if simulator secret is not configured but might be needed
  if FlowChat::Config.simulator_secret.blank?
    Rails.logger.warn "FLOWCHAT_SIMULATOR_SECRET not configured. Simulator mode will be unavailable."
  end
end

# Configure USSD pagination (optional)
FlowChat::Config.ussd.pagination_page_size = 140
FlowChat::Config.ussd.pagination_back_option = "0"
FlowChat::Config.ussd.pagination_back_text = "Back"
FlowChat::Config.ussd.pagination_next_option = "#"
FlowChat::Config.ussd.pagination_next_text = "More"

# Configure resumable sessions (optional)
FlowChat::Config.ussd.resumable_sessions_enabled = true
FlowChat::Config.ussd.resumable_sessions_timeout_seconds = 300 # 5 minutes

# Configure WhatsApp message handling mode based on environment
case Rails.env
when 'development'
  # Development: Use simulator mode for easy testing
  FlowChat::Config.whatsapp.message_handling_mode = :simulator
  
when 'test'
  # Test: Use simulator mode for deterministic testing
  FlowChat::Config.whatsapp.message_handling_mode = :simulator
  
when 'staging'
  # Staging: Use inline mode for real WhatsApp testing
  FlowChat::Config.whatsapp.message_handling_mode = :inline
  
when 'production'
  # Production: Use background mode for high volume
  FlowChat::Config.whatsapp.message_handling_mode = :background
  FlowChat::Config.whatsapp.background_job_class = 'WhatsappMessageJob'
end

# Configure per-environment WhatsApp security
# Note: These are global defaults. You can override per-configuration in your controllers.

# Example of per-environment WhatsApp security configuration:
# 
# For development/test: You might want to disable signature validation for easier testing
# For staging: Enable validation to match production behavior  
# For production: Always enable validation for security
#
# Individual WhatsApp configurations can override these settings:
#
# config = FlowChat::Whatsapp::Configuration.new
# config.access_token = "your_token"
# config.app_secret = "your_app_secret"              # Required for webhook validation
# config.skip_signature_validation = false           # false = validate signatures (recommended)
#
# Development override example:
# config.skip_signature_validation = Rails.env.development? # Only skip in development
