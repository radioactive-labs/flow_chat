# Instrumentation & Monitoring

FlowChat includes a comprehensive instrumentation system for observability, monitoring, and logging.

## Quick Setup

Enable instrumentation in your Rails application:

```ruby
# config/initializers/flowchat.rb
FlowChat.setup_instrumentation!
```

This sets up:
- 📊 **Metrics Collection** - Performance and usage metrics
- 📝 **Structured Logging** - Event-driven logs with context
- 🔍 **Event Tracking** - All framework events instrumented
- ⚡ **Performance Monitoring** - Execution timing and bottleneck detection

## Features

**🎯 Zero Configuration**
- Works out of the box with Rails applications
- Automatic ActiveSupport::Notifications integration
- Thread-safe metrics collection

**📈 Comprehensive Metrics**
- Flow execution counts and timing
- Session creation/destruction rates
- WhatsApp/USSD message volumes
- Cache hit/miss ratios
- Error tracking by type and flow

**🔍 Rich Event Tracking**
- 20+ predefined event types (see [Event Types](#event-types))
- Automatic context enrichment (session ID, flow name, gateway)
- Structured event payloads

**📊 Production Ready**
- Minimal performance overhead
- Thread-safe operations
- Graceful error handling

## Event Types

FlowChat instruments the following events:

### Flow Events
- `flow.execution.start.flow_chat`
- `flow.execution.end.flow_chat`
- `flow.execution.error.flow_chat`

### Session Events
- `session.created.flow_chat`
- `session.destroyed.flow_chat`
- `session.data.get.flow_chat`
- `session.data.set.flow_chat`
- `session.cache.hit.flow_chat`
- `session.cache.miss.flow_chat`

### WhatsApp Events
- `whatsapp.message.received.flow_chat`
- `whatsapp.message.sent.flow_chat`
- `whatsapp.webhook.verified.flow_chat`
- `whatsapp.api.request.flow_chat`
- `whatsapp.media.upload.flow_chat`

### USSD Events
- `ussd.message.received.flow_chat`
- `ussd.message.sent.flow_chat`
- `ussd.pagination.triggered.flow_chat`

## Usage Examples

### Access Metrics

```ruby
# Get current metrics snapshot
metrics = FlowChat.metrics.snapshot

# Flow execution metrics
flow_metrics = FlowChat.metrics.get_category("flows")
puts flow_metrics["flows.executed"] # Total flows executed
puts flow_metrics["flows.execution_time"] # Average execution time

# Session metrics  
session_metrics = FlowChat.metrics.get_category("sessions")
puts session_metrics["sessions.created"] # Total sessions created
puts session_metrics["sessions.cache.hits"] # Cache hit count
```

### Custom Instrumentation in Flows

```ruby
class PaymentFlow < FlowChat::Flow
  def process_payment
    # Instrument custom events in your flows
    instrument("payment.started", {
      amount: payment_amount,
      currency: "USD",
      payment_method: "mobile_money"
    }) do
      # Payment processing logic
      result = process_mobile_money_payment
      
      # Event automatically includes session_id, flow_name, gateway
      result
    end
  end
end
```

### Event Subscribers

```ruby
# config/initializers/flowchat_instrumentation.rb
FlowChat.setup_instrumentation!

# Subscribe to specific events
ActiveSupport::Notifications.subscribe("flow.execution.end.flow_chat") do |event|
  duration = event.duration
  flow_name = event.payload[:flow_name]
  
  # Send to external monitoring service
  ExternalMonitoring.track_flow_execution(flow_name, duration)
end

# Subscribe to all FlowChat events
ActiveSupport::Notifications.subscribe(/\.flow_chat$/) do |name, start, finish, id, payload|
  CustomLogger.log_event(name, payload.merge(duration: finish - start))
end
```

### Integration with Monitoring Services

```ruby
# config/initializers/flowchat_monitoring.rb
FlowChat.setup_instrumentation!

# Export metrics to Prometheus, StatsD, etc.
ActiveSupport::Notifications.subscribe("flow.execution.end.flow_chat") do |event|
  StatsD.increment("flowchat.flows.executed")
  StatsD.timing("flowchat.flows.duration", event.duration)
  StatsD.increment("flowchat.flows.#{event.payload[:flow_name]}.executed")
end

# Track error rates
ActiveSupport::Notifications.subscribe("flow.execution.error.flow_chat") do |event|
  StatsD.increment("flowchat.flows.errors")
  StatsD.increment("flowchat.flows.errors.#{event.payload[:error_class]}")
end
```

## Performance Impact

The instrumentation system is designed for production use with minimal overhead:

- **Event Publishing**: ~0.1ms per event
- **Metrics Collection**: Thread-safe atomic operations
- **Memory Usage**: <1MB for typical applications
- **Storage**: Events are ephemeral, metrics are kept in memory

## Debugging & Troubleshooting

### Enable Debug Logging

```ruby
# config/environments/development.rb
config.log_level = :debug
```

### Reset Metrics

```ruby
# Clear all metrics (useful for testing)
FlowChat.metrics.reset!
```

### Check Event Subscribers

```ruby
# See all active subscribers
ActiveSupport::Notifications.notifier.listeners_for("flow.execution.end.flow_chat")
```

## Testing Instrumentation

```ruby
# test/test_helper.rb
class ActiveSupport::TestCase
  setup do
    # Reset metrics before each test
    FlowChat::Instrumentation::Setup.reset! if FlowChat::Instrumentation::Setup.setup?
  end
end

# In your tests
class FlowInstrumentationTest < ActiveSupport::TestCase
  test "flow execution is instrumented" do
    events = []
    
    # Capture events
    ActiveSupport::Notifications.subscribe(/flow_chat$/) do |name, start, finish, id, payload|
      events << { name: name, payload: payload, duration: (finish - start) * 1000 }
    end
    
    # Execute flow
    processor.run(WelcomeFlow, :main_page)
    
    # Verify events
    assert_equal 2, events.size
    assert_equal "flow.execution.start.flow_chat", events[0][:name]
    assert_equal "flow.execution.end.flow_chat", events[1][:name]
    assert_equal "welcome_flow", events[0][:payload][:flow_name]
  end
end 