# Session Management

FlowChat provides a powerful and flexible session management system that enables persistent conversational state across multiple requests. This document covers the architecture, configuration, and best practices for session management.

## Overview

Sessions in FlowChat store user conversation state between requests, enabling:

- **Multi-step workflows** - Collect information across multiple prompts
- **Context preservation** - Remember user inputs and conversation history
- **Cross-platform consistency** - Same session behavior across USSD and WhatsApp
- **Privacy protection** - Automatic phone number hashing for security
- **Flexible isolation** - Control session boundaries per deployment needs

## Architecture

The session system is built around three core components:

### 1. Session Configuration (`FlowChat::Config::SessionConfig`)

Controls how session IDs are generated and sessions are isolated:

```ruby
# Global session configuration
FlowChat::Config.session.boundaries = [:flow, :gateway, :platform]  # isolation boundaries
FlowChat::Config.session.hash_phone_numbers = true                   # privacy protection
FlowChat::Config.session.identifier = nil                            # platform chooses default
```

### 2. Session Middleware (`FlowChat::Session::Middleware`)

Automatically manages session creation and ID generation based on configuration:

- Generates consistent session IDs based on boundaries and identifiers
- Creates session store instances for each request
- Handles platform-specific defaults (USSD = ephemeral, WhatsApp = durable)
- Provides instrumentation events for monitoring

### 3. Session Stores

Store actual session data with different persistence strategies:

- **`FlowChat::Session::CacheSessionStore`** - Uses Rails cache (recommended)
- **`FlowChat::Session::RailsSessionStore`** - Uses Rails session (limited)

## Session Boundaries

Boundaries control how session IDs are constructed, determining when sessions are shared vs. isolated:

### Available Boundaries

- **`:flow`** - Separate sessions per flow class
- **`:platform`** - Separate sessions per platform (ussd, whatsapp)
- **`:gateway`** - Separate sessions per gateway
- **`:url`** - Separate sessions per request URL (host + path)
- **`[]`** - Global sessions (no boundaries)

### Examples

```ruby
# Default: Full isolation
FlowChat::Config.session.boundaries = [:flow, :gateway, :platform]
# Session ID: "registration_flow:nalo:ussd:abc123"

# Flow isolation only
FlowChat::Config.session.boundaries = [:flow]
# Session ID: "registration_flow:abc123"

# Platform isolation only
FlowChat::Config.session.boundaries = [:platform]
# Session ID: "ussd:abc123"

# Global sessions
FlowChat::Config.session.boundaries = []
# Session ID: "abc123"
```

## Session Identifiers

Identifiers determine what makes a session unique:

### Available Identifiers

- **`nil`** - Platform chooses default (recommended)
  - USSD: `:request_id` (ephemeral sessions)
  - WhatsApp: `:msisdn` (durable sessions)
- **`:msisdn`** - Use phone number (durable sessions)
- **`:request_id`** - Use request ID (ephemeral sessions)

### Platform Defaults

```ruby
# USSD: ephemeral sessions by default
identifier: :request_id
# New session each time USSD times out

# WhatsApp: durable sessions by default  
identifier: :msisdn
# Same session resumes across conversations
```

### Phone Number Hashing

When using `:msisdn` identifier, phone numbers are automatically hashed for privacy:

```ruby
FlowChat::Config.session.hash_phone_numbers = true  # default
# "+256700123456" becomes "a1b2c3d4" (8-character hash)

FlowChat::Config.session.hash_phone_numbers = false
# "+256700123456" used directly (not recommended for production)
```

## Configuration Examples

### Basic USSD Configuration

```ruby
processor = FlowChat::Ussd::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::CacheSessionStore
  
  # Use shorthand for standard durable sessions
  config.use_durable_sessions
end
```

### Custom Session Configuration

```ruby
processor = FlowChat::Ussd::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::CacheSessionStore
  
  # Explicit session configuration
  config.use_session_config(
    boundaries: [:flow, :platform],     # isolate by flow and platform
    hash_phone_numbers: true,           # hash phone numbers for privacy
    identifier: :msisdn                 # use phone number for durable sessions
  )
end
```

### Cross-gateway Sessions

```ruby
processor = FlowChat::Ussd::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::CacheSessionStore
  
  # Allow sessions to work across different gateways
  config.use_session_config(boundaries: [:flow, :platform])
end
```

### Cross-Platform Sessions

```ruby
processor = FlowChat::Ussd::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::CacheSessionStore
  
  # Allow same user to continue on USSD or WhatsApp
  config.use_cross_platform_sessions
  # Equivalent to: boundaries: [:flow]
end
```

### URL-Based Session Isolation

Perfect for multi-tenant applications:

```ruby
processor = FlowChat::Ussd::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::CacheSessionStore
  
  # Isolate sessions by URL (great for multi-tenant SaaS)
  config.use_url_isolation
  # Adds :url to existing boundaries
end
```

**URL Boundary Examples:**
- `tenant1.example.com/ussd` vs `tenant2.example.com/ussd` - Different sessions
- `api.example.com/v1/ussd` vs `api.example.com/v2/ussd` - Different sessions  
- `dev.example.com/ussd` vs `prod.example.com/ussd` - Different sessions

**URL Processing:**
- Combines host + path: `example.com/api/v1/ussd`
- Sanitizes special characters: `tenant-1.com/ussd` → `tenant_1.com/ussd`
- Hashes long URLs (>50 chars): `verylongdomain.../path` → `url_a1b2c3d4`

### Global Sessions

```ruby
processor = FlowChat::Ussd::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::CacheSessionStore
  
  # Single session shared across everything
  config.use_session_config(boundaries: [])
end
```

## Session Stores

### Cache Session Store (Recommended)

Uses Rails cache backend with automatic TTL management:

```ruby
config.use_session_store FlowChat::Session::CacheSessionStore

# Requires Rails cache to be configured
# config/environments/production.rb
config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }
```

**Features:**
- Automatic session expiration via cache TTL
- Redis/Memcached support for distributed deployments
- High performance
- Memory efficient

### Rails Session Store

Uses Rails session for storage (limited scope):

```ruby
config.use_session_store FlowChat::Session::RailsSessionStore
```

**Limitations:**
- Tied to HTTP session lifecycle
- Limited storage capacity
- Not suitable for long-running conversations

## Session Data Usage

### In Flows

Sessions are automatically available in flows:

```ruby
class RegistrationFlow < FlowChat::Flow
  def main_page
    # Store data
    app.session.set("step", "registration")
    app.session.set("user_data", {name: "John", age: 25})
    
    # Retrieve data
    step = app.session.get("step")
    user_data = app.session.get("user_data")
    
    # Check existence
    if app.session.get("completed")
      app.say "Registration already completed!"
      return
    end
    
    # Continue flow...
    name = app.screen(:name) { |prompt| prompt.ask "Name?" }
    app.session.set("name", name)
  end
end
```

### Session Store API

All session stores implement a consistent interface:

```ruby
# Basic operations
session.set(key, value)          # Store data
value = session.get(key)         # Retrieve data
session.delete(key)              # Delete specific key
session.clear                    # Clear all session data
session.destroy                  # Destroy entire session

# Utility methods
session.exists?                  # Check if session has any data
```

## Best Practices

### 1. Choose Appropriate Boundaries

```ruby
# High-traffic public services
boundaries: [:flow, :gateway, :platform]  # Full isolation

# Single-tenant applications
boundaries: [:flow]  # Simpler, allows cross-platform

# Global state services (rare)
boundaries: []  # Shared state across everything
```

### 2. Consider Session Lifecycle

```ruby
# USSD: Short sessions, frequent timeouts
identifier: :request_id  # New session each timeout (default)

# WhatsApp: Long conversations, persistent
identifier: :msisdn     # Resume across days/weeks (default)

# Custom requirements
identifier: :msisdn     # Make USSD durable
identifier: :request_id # Make WhatsApp ephemeral
```

### 3. Handle Session Expiration

```ruby
class RegistrationFlow < FlowChat::Flow
  def main_page
    # Check if session expired
    if app.session.get("user_id").nil?
      restart_registration
      return
    end
    
    # Continue existing session
    continue_registration
  end
  
  private
  
  def restart_registration
    app.say "Session expired. Let's start over."
    # Reset flow to beginning
  end
end
```

### 4. Optimize Session Data

```ruby
# Store only necessary data
app.session.set("user_id", 123)           # Good: minimal data
app.session.set("user", user_object)      # Avoid: large objects

# Clean up when done
def complete_registration
  app.session.set("completed", true)
  app.session.delete("temp_data")  # Clean up temporary data
end
```

### 5. Security Considerations

```ruby
# Always hash phone numbers in production
FlowChat::Config.session.hash_phone_numbers = true

# Use secure cache backends
config.cache_store = :redis_cache_store, {
  url: ENV['REDIS_URL'],
  ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
}

# Set appropriate TTLs
cache_options = { expires_in: 30.minutes }  # Reasonable session timeout
```

## Troubleshooting

### Session Not Persisting

1. **Check session store configuration:**
   ```ruby
   # Ensure session store is configured
   config.use_session_store FlowChat::Session::CacheSessionStore
   ```

2. **Verify cache backend:**
   ```ruby
   # Test cache is working
   Rails.cache.write("test", "value")
   puts Rails.cache.read("test")  # Should output "value"
   ```

3. **Check session boundaries:**
   ```ruby
   # Debug session ID generation
   FlowChat.logger.level = Logger::DEBUG
   # Look for "Session::Middleware: Generated session ID: ..." messages
   ```

### Different Session IDs

1. **Inconsistent request data:**
   - Verify `request.gateway` is consistent
   - Check `request.platform` is set correctly
   - Ensure `request.msisdn` format is consistent

2. **Boundary configuration mismatch:**
   ```ruby
   # Ensure same boundaries across requests
   config.use_session_config(boundaries: [:flow, :platform])
   ```

### Session Data Lost

1. **Cache expiration:**
   ```ruby
   # Increase TTL if needed
   FlowChat::Config.cache = Rails.cache
   # Configure longer expiration in cache store
   ```

2. **Session ID changes:**
   - Check logs for "Generated session ID" messages
   - Verify identifier consistency (`:msisdn` vs `:request_id`)

## Monitoring and Instrumentation

FlowChat emits events for session operations:

```ruby
# Subscribe to session events
ActiveSupport::Notifications.subscribe("session.created.flow_chat") do |event|
  Rails.logger.info "Session created: #{event.payload[:session_id]}"
end

# Monitor session usage
ActiveSupport::Notifications.subscribe(/session\..*\.flow_chat/) do |name, start, finish, id, payload|
  # Track session operations for analytics
  Analytics.track("flowchat.session.#{name.split('.')[1]}", payload)
end
```
