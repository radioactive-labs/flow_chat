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

# Configure USSD pagination (optional)
FlowChat::Config.ussd.pagination_page_size = 140
FlowChat::Config.ussd.pagination_back_option = "0"
FlowChat::Config.ussd.pagination_back_text = "Back"
FlowChat::Config.ussd.pagination_next_option = "#"
FlowChat::Config.ussd.pagination_next_text = "More"

# Configure resumable sessions (optional)
FlowChat::Config.ussd.resumable_sessions_enabled = true
FlowChat::Config.ussd.resumable_sessions_timeout_seconds = 300 # 5 minutes
