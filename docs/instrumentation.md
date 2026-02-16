# Instrumentation

FlowChat provides comprehensive instrumentation via ActiveSupport::Notifications, enabling monitoring, logging, metrics collection, and error tracking across all platforms.

## Quick Start

```ruby
# Subscribe to all FlowChat events
ActiveSupport::Notifications.subscribe(/\.flow_chat$/) do |event|
  Rails.logger.info "FlowChat: #{event.name} - #{event.payload}"
end

# Subscribe to specific events
ActiveSupport::Notifications.subscribe("api.error.flow_chat") do |event|
  Sentry.capture_message("API Error", extra: event.payload)
end
```

## Event Reference

All events are namespaced with `.flow_chat` suffix. Use `FlowChat::Instrumentation::Events` constants for consistency.

### Core Framework Events

| Event | Description | Key Payload |
|-------|-------------|-------------|
| `flow.execution.start` | Flow method begins executing | `flow_name`, `action`, `session_id` |
| `flow.execution.end` | Flow method completes | `flow_name`, `action`, `duration` |
| `flow.execution.error` | Unhandled error in flow | `flow_name`, `error`, `backtrace` |
| `context.created` | New request context created | `request_id`, `platform` |

### Session Events

| Event | Description | Key Payload |
|-------|-------------|-------------|
| `session.created` | New session started | `session_id`, `boundaries` |
| `session.destroyed` | Session ended/cleared | `session_id` |
| `session.data.get` | Session data read | `session_id`, `key` |
| `session.data.set` | Session data written | `session_id`, `key` |
| `session.cache.hit` | Session found in cache | `session_id` |
| `session.cache.miss` | Session not in cache | `session_id` |

### Messaging Events

| Event | Description | Key Payload |
|-------|-------------|-------------|
| `message.received` | Inbound message from user | `platform`, `from`, `message_type` |
| `message.sent` | Outbound message to user | `platform`, `to`, `message_type`, `content_length` |
| `media.upload` | Media file uploaded (WhatsApp) | `platform`, `filename`, `mime_type`, `size` |
| `pagination.triggered` | USSD pagination activated | `session_id`, `page`, `total_pages` |

### Webhook Events

| Event | Description | Key Payload |
|-------|-------------|-------------|
| `webhook.verified` | Webhook signature valid (WhatsApp) | `platform`, `gateway` |
| `webhook.failed` | Webhook validation failed (WhatsApp) | `platform`, `reason` |

### API Events

| Event | Description | Key Payload |
|-------|-------------|-------------|
| `api.error` | API call failed | `platform`, `message`, error details |

### Events for Custom Use

The following event constants are provided for use in your own instrumentation but are not emitted by FlowChat internally:

| Event | Suggested Use | Key Payload |
|-------|---------------|-------------|
| `api.request` | Wrap outbound API calls | `platform`, `endpoint` |
| `middleware.before` | Custom middleware entry | `middleware_class` |
| `middleware.after` | Custom middleware exit | `middleware_class`, `duration` |
| `conversation.assigned` | Intercom assignment tracking | `conversation_id`, `admin_id` |
| `conversation.tagged` | Intercom tag tracking | `conversation_id`, `tag` |
| `conversation.state_changed` | Intercom state tracking | `conversation_id`, `state` |

## API Error Instrumentation

The `api.error` event provides detailed information when API calls fail. This is useful for monitoring, alerting, and debugging integration issues.

### Event Payload by Platform

**Telegram:**
```ruby
{
  platform: :telegram,
  message: "Telegram API error: Unauthorized",
  bot_id: "123456789",
  api_method: "sendMessage",
  error_code: 401,
  error_description: "Unauthorized",
  chat_id: 987654321
}
```

**WhatsApp:**
```ruby
{
  platform: :whatsapp,
  message: "WhatsApp API request failed",
  phone_number_id: "123456789",
  recipient: "+1234567890",
  message_type: "text",
  response_code: "401",
  error_type: "OAuthException",
  error_code: 190,
  error_subcode: 463,
  error_message: "Error validating access token"
}
```

**Intercom:**
```ruby
{
  platform: :intercom,
  message: "Intercom authentication failed",
  app_id: "abc123def",
  conversation_id: "conv_123",
  admin_id: "admin_456"
}
```

### Error Handling Behavior

| Error Type | Telegram | WhatsApp | Intercom |
|------------|----------|----------|----------|
| Invalid credentials | Returns `{"ok"=>false}` | Returns `nil` | Raises `ConfigurationError` |
| API error response | Returns error hash | Returns `nil` | Returns `nil` |
| Network timeout | Re-raises exception | Re-raises exception | Re-raises exception |
| Connection refused | Returns `{"ok"=>false}` | Returns `nil` | Returns `nil` |

**Note:** Network timeouts (`Net::OpenTimeout`, `Net::ReadTimeout`) are intentionally re-raised without instrumentation, allowing callers to implement retry logic at a higher level.

### Example: Error Monitoring

```ruby
# config/initializers/flow_chat_monitoring.rb

ActiveSupport::Notifications.subscribe("api.error.flow_chat") do |event|
  payload = event.payload

  # Log with structured data
  Rails.logger.error({
    event: "flow_chat.api_error",
    platform: payload[:platform],
    message: payload[:message],
    error_code: payload[:error_code],
    recipient: payload[:recipient] || payload[:chat_id] || payload[:conversation_id]
  }.to_json)

  # Send to error tracking service
  Sentry.capture_message(
    "FlowChat API Error: #{payload[:message]}",
    level: :error,
    extra: payload
  )

  # Increment metrics
  StatsD.increment("flow_chat.api_error", tags: ["platform:#{payload[:platform]}"])
end
```

### Example: Rails Error Reporting

FlowChat automatically reports errors to `Rails.error` when available (Rails 7+):

```ruby
# Errors are automatically reported with context:
Rails.error.report(exception, handled: true, context: {
  platform: :whatsapp,
  recipient: "+1234567890",
  message_type: "text"
})
```

You can subscribe to these in your error reporting configuration:

```ruby
# config/initializers/error_reporting.rb
Rails.error.subscribe(MyErrorReporter.new)
```

## Custom Instrumentation

### In Flows

```ruby
class PaymentFlow < FlowChat::Flow
  def process_payment
    amount = app.screen(:amount) { |p| p.ask "Enter amount:" }

    instrument(Events::API_REQUEST, { endpoint: "payment_gateway" }) do
      result = PaymentGateway.charge(amount)

      if result.success?
        app.say "Payment successful!"
      else
        instrument(Events::API_ERROR, {
          message: "Payment failed",
          error_code: result.error_code
        })
        app.say "Payment failed: #{result.error}"
      end
    end
  end
end
```

### In Custom Middleware

```ruby
class MetricsMiddleware
  include FlowChat::Instrumentation

  def initialize(app)
    @app = app
  end

  def call(context)
    @context = context

    instrument(Events::MIDDLEWARE_BEFORE, { middleware_class: self.class.name })

    start_time = Time.current
    result = @app.call(context)
    duration = Time.current - start_time

    instrument(Events::MIDDLEWARE_AFTER, {
      middleware_class: self.class.name,
      duration: duration
    })

    result
  end

  # Required for context enrichment
  attr_reader :context
end
```

### Module-Level Instrumentation

```ruby
# Direct instrumentation without including the module
FlowChat::Instrumentation.instrument("custom.event", {
  custom_key: "custom_value"
})
```

## Payload Enrichment

When instrumenting from objects with a `context` accessor, payloads are automatically enriched with:

- `request_id` - Unique request identifier
- `session_id` - Current session ID
- `flow_name` - Active flow class name
- `gateway` - Gateway handling the request
- `platform` - Platform (`:ussd`, `:whatsapp`, `:telegram`, `:intercom`)

All payloads also include:
- `timestamp` - Event timestamp (`Time.current`)

## Subscribing to Events

### Pattern Matching

```ruby
# All FlowChat events
ActiveSupport::Notifications.subscribe(/\.flow_chat$/) { |event| ... }

# All error events
ActiveSupport::Notifications.subscribe(/error\.flow_chat$/) { |event| ... }

# All session events
ActiveSupport::Notifications.subscribe(/^session\..*\.flow_chat$/) { |event| ... }
```

### Block vs Callable

```ruby
# Block form (simple)
ActiveSupport::Notifications.subscribe("message.sent.flow_chat") do |event|
  puts event.payload
end

# Callable form (for complex subscribers)
class MessageLogger
  def call(event)
    # Access timing info
    puts "Duration: #{event.duration}ms"
    puts "Payload: #{event.payload}"
  end
end

ActiveSupport::Notifications.subscribe("message.sent.flow_chat", MessageLogger.new)
```

## Testing

```ruby
class FlowInstrumentationTest < ActiveSupport::TestCase
  def test_api_error_instrumentation
    events = []

    ActiveSupport::Notifications.subscribe("api.error.flow_chat") do |event|
      events << event
    end

    # Trigger the error condition
    client.send_message_with_invalid_token

    assert_equal 1, events.size
    assert_equal :whatsapp, events.first.payload[:platform]
  ensure
    ActiveSupport::Notifications.unsubscribe("api.error.flow_chat")
  end
end
```

## Production Recommendations

1. **Subscribe early** - Set up subscriptions in initializers before requests arrive
2. **Keep handlers fast** - Use async processing for slow operations (logging to external services)
3. **Filter events** - Only subscribe to events you need to avoid overhead
4. **Use structured logging** - Log payloads as JSON for easier querying
5. **Set up alerting** - Configure alerts on `api.error` events for proactive monitoring
