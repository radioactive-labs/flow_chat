# Async Background Processing

FlowChat supports asynchronous background processing to decouple flow execution from webhook request-response cycles. Webhook endpoints respond immediately (< 100ms) while flows process in background jobs.

## Quick Start

### 1. Create Background Job

Create a job class that inherits from `FlowChat::AsyncJob`:

```ruby
# app/jobs/my_flow_job.rb
class MyFlowJob < FlowChat::AsyncJob
  def execute(controller)
    # Build and run your processor
    processor = FlowChat::Processor.new(controller) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
      config.use_session_config(boundaries: [:flow])
    end

    processor.run MyFlow, :start
  end
end
```

### 2. Enable Async in Controller

```ruby
# app/controllers/webhooks_controller.rb
class WebhooksController < ApplicationController
  def whatsapp
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
      config.use_async MyFlowJob
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

## Gateway Support

| Gateway | Async Support |
|---------|--------------|
| WhatsApp Cloud API | ✅ |
| Intercom API | ✅ |
| HTTP Simple | ✅ |
| USSD Nalo | ❌ (synchronous protocol) |

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
- `perform(request_context:)` entry point
- Creates `BackgroundController` from serialized request
- Calls user's `execute(controller)` method

**BackgroundController**
- Duck-types as Rails controller
- Provides `request`, `params`, `render`, `head` interface
- `params` delegates to `request.params` (mimics Rails controller)
- `render` and `head` are no-ops in background context
- `is_a?(FlowChat::BackgroundController)` returns true for detection

**BackgroundRequest**
- Reconstructs request interface from serialized data
- Provides `params`, `method`, `headers` accessors
- Implements `post?`, `get?` predicates
- Returns nil for `body` and empty hash for `cookies`

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

