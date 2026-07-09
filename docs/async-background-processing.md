# Async Background Processing

FlowChat supports asynchronous background processing to decouple flow execution from webhook request-response cycles. Webhook endpoints respond immediately (< 100ms) while flows process in background jobs.

## Quick Start

### Option 1: Using Factory Pattern (Recommended)

The cleanest approach uses the Factory pattern for centralized configuration:

```ruby
# config/initializers/flow_chat.rb
FlowChat::Factory.register :whatsapp do |controller|
  processor = FlowChat::Processor.new(controller) do |config|
    config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
    config.use_session_store FlowChat::Session::CacheSessionStore
    config.use_session_config(boundaries: [:flow])
    config.use_async(factory: :whatsapp)  # Self-referencing for async
  end
  processor.run(WhatsAppFlow, :start)
end

# app/controllers/webhooks_controller.rb
class WebhooksController < ApplicationController
  def whatsapp
    FlowChat::Factory.execute(:whatsapp, controller: self)
  end
end
```

**Benefits:**
- No custom job class needed
- Configuration defined once in initializer
- Works seamlessly in both webhook and background contexts

See [Factory Pattern Documentation](factory-pattern.md) for more details.

### Option 2: Custom Job Class

For advanced use cases, create a custom job class:

```ruby
# app/jobs/my_flow_job.rb
class MyFlowJob < FlowChat::AsyncJob
  def execute(controller, **job_params)
    # Access job params passed from use_async
    deployment_id = job_params[:deployment_id]

    # Build and run your processor
    processor = FlowChat::Processor.new(controller) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
      config.use_session_config(boundaries: [:flow])
    end

    processor.run MyFlow, :start
  end
end

# app/controllers/webhooks_controller.rb
class WebhooksController < ApplicationController
  def whatsapp
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
      config.use_async MyFlowJob, deployment_id: params[:deployment_id]
    end
    processor.run(MyFlow, :start)
  end
end
```

## Configuration

### Session Store

Use a centralized cache store e.g. `CacheSessionStore` for async processing:

```ruby
config.use_session_store FlowChat::Session::CacheSessionStore
```

### ActiveJob Backend

```ruby
# config/application.rb
config.active_job.queue_adapter = :sidekiq  # or :resque, :delayed_job
```

### Queue Configuration

Set queue in job class:

```ruby
class MyFlowJob < FlowChat::AsyncJob
  queue_as :support_flows

  def execute(controller)
    # ...
  end
end
```

Configure priorities:

```ruby
# config/sidekiq.yml
:queues:
  - [critical, 2]
  - [support_flows, 1]
  - [default, 1]
```

## Passing Parameters to Jobs

### Job Params

When using custom job classes, you can pass additional parameters via `use_async`:

```ruby
# In controller
config.use_async(MyFlowJob, deployment_id: 123, flow_name: "SupportFlow")

# In job execute method
class MyFlowJob < FlowChat::AsyncJob
  def execute(controller, **job_params)
    deployment_id = job_params[:deployment_id]  # => 123
    flow_name = job_params[:flow_name]          # => "SupportFlow"

    # Use params for business logic
    processor = FlowChat::Processor.new(controller) do |config|
      # ... configuration
    end
    processor.run(MyFlow, :start)
  end
end
```

**Note:** Request params (from `controller.params`) are automatically available in the background job via the reconstructed `controller.params`. Job params are for additional data specific to job execution logic.

### Factory with GenericAsyncJob

When using `factory:` param, additional params are ignored by `GenericAsyncJob` but can be used by the factory:

```ruby
config.use_async(factory: :whatsapp, extra_data: "value")
# extra_data is passed to perform but not used by GenericAsyncJob
```

## Gateway Support

| Gateway | Async Support | Nil Response Handling |
|---------|--------------|----------------------|
| WhatsApp Cloud API | ✅ | ✅ Returns silently |
| Intercom API | ✅ | ✅ Returns silently |
| HTTP Simple | ✅ | ✅ Returns `{type: :skip}` JSON |
| USSD Nalo | ❌ (synchronous protocol) | ❌ Requires immediate response |

### Middleware Nil Response Handling

Async-capable gateways support middleware that returns `nil` instead of a response tuple. This is useful for middleware that handles responses directly (e.g., `AgentHandoffMiddleware`):

```ruby
class AgentHandoffMiddleware
  def call(context)
    if should_handoff_to_agent?
      # Middleware handles response directly
      send_to_agent(context)
      return nil  # Signal that response was handled
    end

    @app.call(context)  # Continue to next middleware
  end
end
```

When middleware returns `nil`:
- **HTTP Simple**: Returns JSON response `{type: :skip, session_id, user_id, timestamp}`
- **WhatsApp/Intercom**: Returns silently (message already sent by middleware)
- **USSD**: Not supported - synchronous protocol requires immediate response

**Note**: USSD cannot support middleware that returns nil because the USSD protocol requires an immediate synchronous response to every request.

## How It Works

### Execution Paths

FlowChat's async system automatically routes requests through one of three paths:

#### 1. Webhook → Async Job (async enabled, webhook context)

```
1. Webhook request arrives at controller
2. Processor.run() called with use_async configured
3. Gateway checks: should_enqueue_async?
   - Not in background? ✅
   - Async enabled? ✅
   - Gateway supports async? ✅
4. Gateway serializes request context:
   - params (session_id, user_id, input, etc.)
   - method (POST/GET)
   - headers (Content-Type, User-Agent)
5. Gateway enqueues job: JobClass.perform_later(request_context: {...})
6. Gateway returns immediately (< 100ms)
7. Background worker picks up job
8. AsyncJob.perform creates BackgroundController from request_context
9. User's execute() called with controller
10. Flow processes normally with reconstructed request
```

#### 2. Background Job → Inline (async enabled, background context)

```
1. Background job executes
2. AsyncJob.perform creates BackgroundController
3. User's execute() creates new processor
4. Processor.run() called
5. Gateway checks: should_enqueue_async?
   - Not in background? ❌ (BackgroundController detected)
   - Async enabled? ✅
   - Gateway supports async? ✅
6. Gateway processes inline (prevents double-enqueueing)
7. Flow executes, calls controller.render (no-op in background)
8. Job completes
```

#### 3. Webhook → Inline (async not configured)

```
1. Webhook request arrives
2. Processor.run() called without use_async
3. Gateway checks: should_enqueue_async?
   - Not in background? ✅
   - Async enabled? ❌
   - Gateway supports async? ✅
4. Gateway processes inline
5. Flow executes
6. Response returned to webhook provider
```

### Key Components

**AsyncJob**
- Base class users inherit from
- `perform(request_context:, **job_params)` entry point
- Creates `BackgroundController` from serialized request
- Calls user's `execute(controller, **job_params)` method

**GenericAsyncJob**
- Built-in job that uses Factory pattern
- Automatically used when `use_async(factory: :name)` is called
- Executes registered factory in background context
- Validates factory is registered before execution

**BackgroundController**
- Duck-types as Rails controller
- Provides `request`, `params`, `render`, `head` interface
- `params` delegates to `request.params` (mimics Rails controller)
- `render` and `head` are no-ops in background context
- `is_a?(FlowChat::BackgroundController)` returns true for detection

**BackgroundRequest**
- Reconstructs full Rails request interface from serialized data
- Provides `params`, `method`, `headers`, `host`, `path`, `remote_ip` accessors
- HTTP method predicates: `post?`, `get?`, `head?`
- Rails compatibility methods: `request_method`, `user_agent`, `ssl?`
- Request body support: `body` returns object with `read()` and `rewind()` methods
- Body content is serialized from webhook and reconstructed in background
- Returns empty hash for `cookies` (not available in background context)

**GatewayAsyncSupport**
- Concern mixed into all gateways
- `should_enqueue_async?` decision logic
- `in_background?` detection via `BackgroundController`
- `enqueue_async_job` serializes and enqueues
- `async_supported?` override for gateways like USSD

### Decision Logic

The gateway's `should_enqueue_async?` method checks three conditions:

```ruby
def should_enqueue_async?
  processor = @context["processor"]

  !in_background? &&                # Prevent double-enqueueing
    processor&.async_enabled? &&    # User opted in
    async_supported?                # Gateway allows it
end
```

**All three must be true** to enqueue. If any condition is false, the flow processes inline.

This ensures:
- Background jobs never enqueue another job
- Users explicitly opt in per processor
- Synchronous protocols (USSD) always process inline

