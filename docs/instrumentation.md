# Instrumentation

FlowChat emits `ActiveSupport::Notifications` events at each stage of a request, so you can feed metrics, traces, and structured logs into your own backend. The events fire whether or not anything subscribes; FlowChat also ships a log subscriber and a metrics collector that subscribe for you.

## Event names

Every FlowChat event is published under its name with a `.flow_chat` suffix. The name in the table is what you pass to `instrument`; the string you subscribe to adds the suffix, for example `flow.execution.end.flow_chat`.

| Event | When it fires |
|---|---|
| `flow.execution.start` | A flow action begins. |
| `flow.execution.end` | A flow action finishes (carries `duration`). |
| `flow.execution.error` | A flow action raised. |
| `context.created` | A request context is built. |
| `session.created` | A session is created. |
| `session.destroyed` | A session is destroyed (flow terminated). |
| `session.data.get` / `session.data.set` | A session value is read or written. |
| `session.cache.hit` / `session.cache.miss` | A session cache lookup. |
| `message.received` | An inbound message arrives (text or an attachment). |
| `message.sent` | A response is sent to the user. |
| `webhook.verified` / `webhook.failed` | A gateway verified or rejected a webhook. |
| `api.request` / `api.error` | An outbound platform API call, or its failure. |
| `media.upload` | Media is uploaded to a platform. |
| `pagination.triggered` | A USSD response was split into pages. |

Payloads are enriched with `request_id`, `session_id`, `flow_name`, `gateway`, and `platform` when the context has them, plus a `timestamp`.

## Subscribing

Subscribe with `ActiveSupport::Notifications`, remembering the `.flow_chat` suffix:

```ruby
ActiveSupport::Notifications.subscribe("flow.execution.end.flow_chat") do |*, payload|
  StatsD.timing("flow_chat.flow.#{payload[:flow_name]}", payload[:duration])
end

ActiveSupport::Notifications.subscribe("message.received.flow_chat") do |*, payload|
  StatsD.increment("flow_chat.message.received.#{payload[:platform]}")
end
```

## Built-in metrics

`FlowChat.metrics` returns a metrics collector that subscribes to the events above and keeps running counters and timings (flows executed, errors by class, sessions created by gateway, cache hits, and so on). Read a snapshot:

```ruby
FlowChat.metrics.snapshot                 # => a Hash of counters and timings
FlowChat.metrics.get_category("flows")    # => just the flows.* metrics
```

FlowChat also ships a `LogSubscriber` that logs the same events through `FlowChat::Config.logger`. Both are wired up by `FlowChat::Instrumentation::Setup`; call `FlowChat.setup_instrumentation!` during boot to enable them, or access `FlowChat.metrics` to start the collector on first use.

## Related

- [Configuration](configuration.md)
- [Architecture](architecture.md)
