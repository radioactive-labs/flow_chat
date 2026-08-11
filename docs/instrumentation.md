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
| `message.delivery_failed` | A reply the flow produced that the platform would not take. |
| `message.status` | A platform's own report of what became of a message we sent. |
| `webhook.verified` / `webhook.failed` | A gateway verified or rejected a webhook. |
| `api.request` / `api.error` | An outbound platform API call, or its failure. |
| `media.upload` | Media is uploaded to a platform. |
| `pagination.triggered` | A USSD response was split into pages. |
| `webhook.received` | A verified webhook this gateway does not model, handed on whole. |

Payloads are enriched with `request_id`, `session_id`, `flow_name`, `gateway`, and `platform` when the context has them, plus a `timestamp`.

## Webhooks that are not messaging

FlowChat's job is messaging: the inbound turn, the reply it produces, and what became of that reply. A platform sends a great deal more. WhatsApp alone will report account bans, template approvals, phone number quality, imported chat history, contact address books, and replies a human typed in the WhatsApp Business App, and it adds new fields regularly.

None of that is a customer turn, so **none of it runs a flow**, and none of it is interpreted here. FlowChat verifies the signature, answers the platform, and publishes the change under `webhook.received` with the field that named it. What it means is your application's decision:

```ruby
ActiveSupport::Notifications.subscribe("webhook.received.flow_chat") do |*, payload|
  case payload[:field]
  when "smb_message_echoes"
    # A human answered from the WhatsApp Business App. Most applications will want
    # to stop the bot replying on top of them.
    MyApp::Echoes.record(payload[:business_phone_number_id], payload[:value]["message_echoes"])
  when "history"
    MyApp::HistoryImport.enqueue(payload[:business_phone_number_id], payload[:value]["history"])
  when "account_update"
    MyApp::Connections.review(payload[:business_phone_number_id], payload[:value])
  end
end
```

The payload carries `field`, the whole `value`, and the business phone number when the change names one. Account-level changes do not name one, so expect it to be nil there.

Subscribing to a field costs nothing here: an unmodelled field is published whether or not anything listens, and logged at info so a subscription you have not written yet is still visible. Adding support for a new field is a change in your application, not a new release of this gem.

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

## Delivery callbacks

Events are broadcasts and carry no context, because anyone may subscribe and the context holds the gateway client and the raw inbound body. When the application that owns the turn needs to reach its own records, it uses a callback instead.

A gateway that delivers out of band (Telegram, WhatsApp, Intercom) sends after the middleware stack has unwound. So a row the application wrote during the turn was written before anything knew whether the send worked, or what the platform would call it. These two callbacks are the only places that know:

```ruby
FlowChat::Config.on_delivery_success = lambda do |context, result|
  id = context[FlowChat::Instrumentation::DELIVERED_MESSAGE_ID_KEY]
  MyApp::Message.find(context["myapp.bot_message_id"]).update!(platform_message_id: id) if id
end

FlowChat::Config.on_delivery_failure = lambda do |context, error|
  MyApp::Message.find(context["myapp.bot_message_id"]).update!(status: :failed, error: error.message)
end
```

`DELIVERED_MESSAGE_ID_KEY` is `"delivery.platform_message_id"`, and every out-of-band gateway sets it to whatever its own platform called the message: WhatsApp's `wamid`, Telegram's numeric `message_id`, Intercom's conversation part id. It is nil when a platform names none. Reading one key is the point, so an application does not carry a case statement over platforms.

HTTP and USSD set nothing, since their reply travels in the response they are already returning and has no separate delivery to succeed or fail.

Neither callback may change what happened. `on_delivery_success` cannot alter the send's return value, `on_delivery_failure` cannot replace the delivery error, and an exception raised in either is logged and dropped.

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
