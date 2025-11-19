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
- Session stores: `CacheSessionStore`
- Session IDs generated based on boundaries and identifiers

#### Factory Pattern (`lib/flow_chat/factory.rb`)
- Centralized processor configuration system
- Register configurations once, use everywhere
- Methods: `register(name, &block)`, `execute(name, controller:)`
- Eliminates duplication between webhook and background contexts
- Works seamlessly with `GenericAsyncJob` for async processing

#### Async Background Processing (`lib/flow_chat/async_job.rb`, `gateway_async_support.rb`, `generic_async_job.rb`)
- Decouple flow processing from webhook request-response cycles
- Base class: `FlowChat::AsyncJob` for custom background jobs
- `GenericAsyncJob`: Built-in job that uses Factory pattern (no custom job needed)
- `BackgroundController` mimics controller interface in background context
- `GatewayAsyncSupport` concern for gateways to detect and enqueue async jobs
- Automatic detection: async enqueue, background execute, or inline processing
- Supported gateways: WhatsApp Cloud API, Intercom API, HTTP Simple (not USSD)

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
  config.use_session_store FlowChat::Session::CacheSessionStore
  config.use_session_config(boundaries: [:flow], identifier: :msisdn)
end
```

#### Multi-Platform Support
Same flow code works across USSD, WhatsApp, and HTTP by using platform-agnostic `app.screen()` calls.

#### Factory Pattern with Async
The recommended approach for async processing using centralized configuration:

```ruby
# Register factory once in initializer
FlowChat::Factory.register :whatsapp do |controller|
  processor = FlowChat::Processor.new(controller) do |config|
    config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
    config.use_session_store FlowChat::Session::CacheSessionStore
    config.use_async(factory: :whatsapp)  # Self-referencing for async
  end
  processor.run(WhatsAppFlow, :start)
end

# Use in webhook controller - one line!
FlowChat::Factory.execute(:whatsapp, controller: self)
```

**How it works:**
1. Webhook calls `Factory.execute(:whatsapp)`
2. Factory builds processor with `use_async(factory: :whatsapp)`
3. Gateway enqueues `GenericAsyncJob` with `factory: :whatsapp` param
4. Background job executes `Factory.execute(:whatsapp)` again
5. Gateway detects background context and processes inline

**Benefits:**
- No custom job class needed (`GenericAsyncJob` handles it automatically)
- Configuration defined once, works in both webhook and background contexts
- Webhook returns immediately (< 100ms), flow processes in background
- Automatic prevention of double-enqueueing

See [docs/factory-pattern.md](docs/factory-pattern.md) and [docs/async-background-processing.md](docs/async-background-processing.md) for details.

#### Custom Async Jobs
For advanced cases, create custom job classes with job params:

```ruby
class MyFlowJob < FlowChat::AsyncJob
  def execute(controller, **job_params)
    deployment_id = job_params[:deployment_id]
    # ... custom logic with job params
  end
end

# Use with job params
config.use_async(MyFlowJob, deployment_id: 123)
```

## File Structure

### Core Library (`lib/flow_chat/`)
- `processor.rb` - Main orchestrator, middleware stack builder
- `app.rb` - Unified conversation interface
- `flow.rb` - Base flow class
- `executor.rb` - Flow execution and interrupt handling
- `context.rb` - Request context management
- `config.rb` - Global configuration
- `factory.rb` - Centralized processor configuration registry
- `async_job.rb` - Background processing base class and controllers
- `generic_async_job.rb` - Factory-based async job (no custom class needed)
- `gateway_async_support.rb` - Async detection and enqueueing concern for gateways

### Platform Gateways
- `ussd/gateway/nalo.rb` - USSD platform integration (async not supported)
- `whatsapp/gateway/cloud_api.rb` - WhatsApp Business API integration (async supported)
- `http/gateway/simple.rb` - HTTP/JSON API integration (async supported)
- `intercom/gateway/intercom_api.rb` - Intercom customer support integration (async supported)
- All gateways include `GatewayAsyncSupport` concern for unified async handling

### Session Management (`session/`)
- `middleware.rb` - Session boundary and ID generation
- `rails_session_store.rb` - Rails session integration
- `cache_session_store.rb` - Rails cache integration

### Platform-Specific (`ussd/`, `whatsapp/`, `http/`, `intercom/`)
- `renderer.rb` - Platform-specific response formatting
- `middleware/` - Platform-specific processing logic
- `intercom/client.rb` - Intercom REST API integration
- `intercom/configuration.rb` - Intercom credentials and settings
- `intercom/conversation_manager.rb` - Generic conversation management utilities

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

### Global Configuration
```ruby
# Logger injection into middleware stack (defaults to true in Rails development)
FlowChat::Config.inject_middleware_logger = true

# Other global configs
FlowChat::Config.logger = Rails.logger
FlowChat::Config.combine_validation_error_with_message = true
```

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

### Intercom Integration

FlowChat provides comprehensive Intercom integration for customer support workflows with proper webhook validation and API client functionality.

#### Configuration
```ruby
# Rails credentials (config/credentials.yml.enc)
intercom:
  access_token: "your_intercom_access_token"
  client_secret: "your_intercom_client_secret"
  skip_signature_validation: false  # Optional: disable webhook validation for testing

# Or environment variables
INTERCOM_ACCESS_TOKEN=your_intercom_access_token
INTERCOM_CLIENT_SECRET=your_intercom_client_secret
INTERCOM_SKIP_SIGNATURE_VALIDATION=false
```

#### Gateway Setup
```ruby
# Basic Intercom gateway setup (default webhook topics)
config.use_gateway FlowChat::Intercom::Gateway::IntercomApi
config.use_session_config(boundaries: [:conversation], identifier: :conversation_id)

# With custom configuration
intercom_config = FlowChat::Intercom::Configuration.get(:my_config)
config.use_gateway FlowChat::Intercom::Gateway::IntercomApi, intercom_config

# Additional webhook topics (e.g., to include admin events)
# Note: Default topics (user.created, user.replied) are always included
config.use_gateway FlowChat::Intercom::Gateway::IntercomApi, nil, [
  "conversation.admin.assigned",
  "conversation.admin.replied"
]

# Custom config AND additional webhook topics
config.use_gateway FlowChat::Intercom::Gateway::IntercomApi, intercom_config, [
  "conversation.admin.assigned",
  "conversation.admin.replied"
]
```

**Default Webhook Topics:**
- `conversation.user.created` - New conversation started by user
- `conversation.user.replied` - User replied in existing conversation

**Additional Available Topics:**
- `conversation.admin.assigned` - Admin assigned to conversation
- `conversation.admin.replied` - Admin replied to conversation
- `conversation.admin.closed` - Admin closed conversation
- See [Intercom webhook docs](https://developers.intercom.com/docs/references/webhooks/webhook-models/) for full list

#### Webhook Setup
1. Add your HTTPS endpoint URL in Intercom Developer Hub → Configure → Webhooks
2. Intercom validates your endpoint with HEAD request (handled automatically)
3. Webhook notifications are validated using X-Hub-Signature with client_secret

#### FlowChat Client API
The FlowChat Intercom client provides only the core methods needed by the gateway:

```ruby
# Access within a flow via context
client = context["intercom.client"]
conversation_id = context["request.conversation_id"]

# Send a message (used by gateway automatically)
client.send_message(conversation_id, "Hello!", choices: nil, media: nil)
```

**Note:** Conversations are automatically assigned to the configured admin when messages are sent (Intercom's default behavior). Each admin can change this in their personal settings if desired.

**Important:** For business logic (tags, assignment, state management, fetching conversations), use the official `intercom` gem directly in your application:

```ruby
# In your application code, use the official gem for business logic
intercom = Intercom::Client.new(token: access_token)

# Tag management
intercom.tags.tag(name: "AI_HANDLING", conversations: [{id: conversation_id}])

# Assignment (override default auto-assignment)
intercom.conversations.reply(id: conversation_id, message_type: "assignment", admin_id: admin_id)

# State management
intercom.conversations.reply(id: conversation_id, message_type: "closed")

# Fetch conversation details
conversation = intercom.conversations.find(id: conversation_id)
```

#### Error Handling
- Rate limiting: `RateLimitError` with retry-after information
- Authentication: `ConfigurationError` for invalid tokens
- API errors: Proper handling for Intercom gem exceptions (ResourceNotFound, UnauthorizedError, etc.)

## Instrumentation

FlowChat includes comprehensive instrumentation via `FlowChat::Instrumentation`:
- Flow execution events
- Session creation events  
- Platform-specific metrics
- Error tracking and logging