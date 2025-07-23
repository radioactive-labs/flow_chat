# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Testing
- `rake test` or `bundle exec rake test` - Run all tests
- `ruby -Itest test/unit/specific_test.rb` - Run a single test file
- `ruby -Itest test/unit/specific_test.rb -n test_method_name` - Run a specific test method

### Gem Development
- `bundle install` - Install dependencies
- `rake build` - Build the gem
- `rake release` - Build and release the gem (requires proper credentials)

### Rails Integration Testing
- Use `rails runner` instead of `rails console` for scripting
- For production logs, use Rails.logger with block syntax: `Rails.logger.warn { "message" }`

## Architecture Overview

FlowChat is a Rails framework for building conversational interfaces across multiple platforms (USSD, WhatsApp, HTTP) using a **composition-based architecture** with **pluggable gateways**.

### Core Components

#### Processor (`lib/flow_chat/processor.rb`)
- Central orchestrator that builds and executes the middleware stack
- Configures gateways, session stores, and middleware
- Entry point: `FlowChat::Processor.new(controller) do |config|`

#### Gateway
- Platform-specific request/response handling
- Built-in gateways: `FlowChat::Ussd::Gateway::Nalo`, `FlowChat::Whatsapp::Gateway::CloudApi`, `FlowChat::Http::Gateway::Simple`
- Custom gateways implement: `initialize(app, *args)` and `call(context)`

#### App (`lib/flow_chat/app.rb`)
- Unified interface for flows to interact with users
- Key method: `screen(key) { |prompt| ... }` for conversation logic
- Platform-agnostic accessors: `msisdn`, `user_id`, `platform`, etc.

#### Flow (`lib/flow_chat/flow.rb`)
- Simple base class containing conversation logic
- Initialize with `app` instance, implement flow methods

#### Session (`lib/flow_chat/session/`)
- Configurable session boundaries: `:flow`, `:platform`, `:gateway`, `:url`
- Session stores: `RailsSessionStore`, `CacheSessionStore`
- Session IDs generated based on boundaries and identifiers

### Middleware Stack Architecture

```
Gateway -> Session::Middleware -> Custom Middleware -> Executor -> Flow
```

- **Gateway**: Parses platform-specific requests, renders responses
- **Session::Middleware**: Manages session boundaries and storage
- **Custom Middleware**: Business logic, authentication, logging
- **Executor**: Instantiates flows and handles interrupts
- **Flow**: Business logic using `app.screen()` for conversation

### Key Patterns

#### Screen-Based Navigation
```ruby
def registration_flow
  email = app.screen(:email) { |p| p.ask "Enter email:", validate: email_validator }
  name = app.screen(:name) { |p| p.ask "Enter name:", transform: ->(input) { input.titleize } }
  app.say "Welcome #{name}!"
end
```

#### Platform Configuration
```ruby
processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::RailsSessionStore
  config.use_session_config(boundaries: [:flow], identifier: :msisdn)
end
```

#### Multi-Platform Support
Same flow code works across USSD, WhatsApp, and HTTP by using platform-agnostic `app.screen()` calls.

## File Structure

### Core Library (`lib/flow_chat/`)
- `processor.rb` - Main orchestrator, middleware stack builder
- `app.rb` - Unified conversation interface
- `flow.rb` - Base flow class
- `executor.rb` - Flow execution and interrupt handling
- `context.rb` - Request context management
- `config.rb` - Global configuration

### Platform Gateways
- `ussd/gateway/nalo.rb` - USSD platform integration
- `whatsapp/gateway/cloud_api.rb` - WhatsApp Business API integration
- `http/gateway/simple.rb` - HTTP/JSON API integration

### Session Management (`session/`)
- `middleware.rb` - Session boundary and ID generation
- `rails_session_store.rb` - Rails session integration
- `cache_session_store.rb` - Rails cache integration

### Platform-Specific (`ussd/`, `whatsapp/`, `http/`)
- `renderer.rb` - Platform-specific response formatting
- `middleware/` - Platform-specific processing logic

### Testing (`test/`)
- `test_helper.rb` - Test setup with mock Rails environment
- `unit/` - Unit tests for individual components
- `integration/` - Integration tests for full flow scenarios
- `e2e/` - End-to-end tests for platform-specific features

## Testing Approach

- Uses Minitest with custom test helpers
- Mock Rails environment for testing without full Rails app
- Test flows using `mock_controller` and session store mocks
- Platform-specific tests verify gateway behavior
- Integration tests verify full request/response cycles

## Configuration Patterns

### Session Configuration
```ruby
config.use_session_config(
  boundaries: [:flow, :platform],  # Session isolation
  identifier: :msisdn,              # Session key type  
  hash_identifiers: true            # Privacy protection
)
```

### Multi-Tenancy Support
```ruby
config.use_url_isolation  # tenant1.app.com vs tenant2.app.com
config.use_cross_platform_sessions  # Share sessions between USSD/WhatsApp
config.use_durable_sessions  # Use user_id instead of request_id
```

## Instrumentation

FlowChat includes comprehensive instrumentation via `FlowChat::Instrumentation`:
- Flow execution events
- Session creation events  
- Platform-specific metrics
- Error tracking and logging