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

## Reacting to `api.error`

The `message` on an `api.error` payload is prose, written for someone reading
logs. Do not branch on it: rewording a log line would change your behaviour.
Read these instead.

| key | meaning |
|---|---|
| `error_class` | The exception's class, whenever one was raised. |
| `error_type` | What kind of failure it is, named by the adapter. Intercom reports `authentication`, `resource_not_found` and `server_error`; WhatsApp passes through Meta's own `type`, such as `OAuthException`. |
| `error_code` | The platform's own code. Telegram's `error_code`, Meta's `code`, Intercom's HTTP status. |

WhatsApp also carries `error_subcode` and `error_message` from Meta, and
Telegram carries `error_description`. Identify the connection from
`phone_number_id`, `bot_id` or `app_id` as appropriate.

Not every failure reports. Network timeouts are re-raised so your own retry
logic sees them, and an Intercom rate limit raises `RateLimitError` rather than
reporting, so a subscriber reacting to `api.error` will not mistake either for
a dead credential.

```ruby
ActiveSupport::Notifications.subscribe("api.error.flow_chat") do |*, payload|
  next unless payload[:error_type] == "authentication"

  AlertOwner.call(platform: payload[:platform], app_id: payload[:app_id])
end
```

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
