# Configuration

FlowChat has two layers of configuration: global settings on `FlowChat::Config`, set once during boot, and per-processor settings passed to the `FlowChat::Processor.new` block for each webhook.

## Global configuration

Set these once, for example in `config/initializers/flow_chat.rb`.

| Option | Default | What it controls |
|---|---|---|
| `FlowChat::Config.logger` | `Logger.new($stdout)` | The logger FlowChat writes to. Set it to `Rails.logger` to fold FlowChat logs into your app's. |
| `FlowChat::Config.cache` | `nil` | The cache backend the session store reads and writes. Required: `CacheSessionStore` raises without it. Set it to `Rails.cache` or any store with the same interface. |
| `FlowChat::Config.simulator_secret` | `nil` | Secret that enables the local web simulator. The simulator stays off until this is set. See [testing.md](testing.md). |
| `FlowChat::Config.combine_validation_error_with_message` | `true` | When `true`, a rejected input re-prompts with the validation error followed by the original prompt. When `false`, only the error is shown. |
| `FlowChat::Config.inject_middleware_logger` | `true` in Rails development, else `false` | Whether a logging middleware is inserted into the stack automatically. |

```ruby
# config/initializers/flow_chat.rb
FlowChat::Config.cache = Rails.cache
FlowChat::Config.logger = Rails.logger
FlowChat::Config.simulator_secret = Rails.application.credentials.flow_chat_simulator_secret
```

## USSD configuration

`FlowChat::Config.ussd` controls how USSD responses are paginated. USSD messages are length-limited, so FlowChat splits long output into pages and adds navigation options.

| Option | Default | What it controls |
|---|---|---|
| `pagination_page_size` | `140` | Maximum characters per USSD page before FlowChat splits the response. |
| `pagination_next_option` | `"#"` | The input a user sends to see the next page. |
| `pagination_next_text` | `"More"` | The label shown next to the next-page option. |
| `pagination_back_option` | `"0"` | The input a user sends to go to the previous page. |
| `pagination_back_text` | `"Back"` | The label shown next to the previous-page option. |

```ruby
FlowChat::Config.ussd.pagination_page_size = 160
```

## WhatsApp configuration

`FlowChat::Config.whatsapp` holds the WhatsApp Cloud API base URL. Per-tenant credentials (access token, phone number id, app secret, verify token) are passed to the gateway, not set here. See [platforms/whatsapp.md](platforms/whatsapp.md).

| Option | Default | What it controls |
|---|---|---|
| `api_base_url` | `"https://graph.facebook.com/v23.0"` | The Cloud API version and host the WhatsApp client calls. |

## HTTP configuration

`FlowChat::Config.http` holds defaults for the HTTP gateway used in testing and custom integrations. See the platform guides for the full request and response shapes.

| Option | Default | What it controls |
|---|---|---|
| `default_gateway` | `:simple` | The HTTP gateway used when none is named. |
| `request_timeout` | `30` | Request timeout in seconds. |
| `response_format` | `:json` | The response serialization format. |

## Sessions

A session holds the answers a flow has collected so far. FlowChat looks the session up by an id it builds on every request from two things: a set of boundaries and an identifier.

`FlowChat::Config.session` sets the defaults.

| Option | Default | What it controls |
|---|---|---|
| `boundaries` | `[:flow, :gateway, :platform]` | Which dimensions separate one session from another (see below). |
| `hash_identifiers` | `true` | Whether the identifier (often a phone number) is hashed into the session id rather than stored in the clear. |
| `identifier` | `nil` | Which request value identifies the user. `nil` lets the platform choose: WhatsApp uses `:msisdn`, the others use `:request_id`. |
| `session_id_proc` | `nil` | A callable that builds the session id from the context directly, bypassing boundaries and identifier. |

### How the session id is built

FlowChat sets the session id one of three ways, in order of precedence:

1. If `context["session.id"]` is already set, that value is used verbatim (a manual override).
2. If you passed a block to `use_session_config`, its return value is used verbatim. Boundaries and identifier are skipped entirely.
3. Otherwise the id is built from the boundaries and the identifier, described below.

Think of the built id as `boundaries` followed by `identifier`: the boundaries describe the context a session lives in (the walls that separate it), and the identifier is who the session belongs to. The parts are joined with `:` in this fixed order, and a part is included only when its boundary is enabled and its value is present:

```
flow_name : platform : gateway : url : identifier
```

The order of the parts is fixed regardless of the order you list boundaries in. With the default boundaries `[:flow, :gateway, :platform]`, a WhatsApp user in `RegistrationFlow` gets:

```
registration_flow:whatsapp:whatsapp_cloud_api:a1b2c3d4
     (flow)          (platform)     (gateway)   (hashed msisdn)
```

### What each boundary isolates

A boundary is a wall. Include it and two requests that differ on that dimension get separate sessions; drop it and they share one session, provided the identifier matches.

| Boundary | Segment | Adding it separates sessions by | Drop it when |
|---|---|---|---|
| `:flow` | `context["flow.name"]` | flow class, so `RegistrationFlow` and `SurveyFlow` never share state | you want one session shared across all flows (rare) |
| `:platform` | `:ussd`, `:whatsapp`, and so on | platform, so the same person on USSD and on WhatsApp gets two sessions | you want one conversation to span platforms |
| `:gateway` | `:nalo`, `:whatsapp_cloud_api`, and so on | gateway, so two gateways on the same platform (for example two USSD aggregators) do not collide | you are consolidating gateways and want them to share |
| `:url` | normalized `host + path` | host and path, for per-tenant or per-endpoint isolation (`tenant1.app.com` vs `tenant2.app.com`) | single tenant, single endpoint |

The `:url` segment is `host + path` with the leading slash removed and any character outside `[a-zA-Z0-9._-]` replaced by `_`. If that exceeds 50 characters it becomes the first 41 characters plus an 8-character SHA256 suffix, so it stays bounded but still recognizable.

### The identifier

The identifier is chosen independently of the boundaries and always comes last. Its type is the `identifier` option, or a platform default when unset: WhatsApp uses `:msisdn`, every other platform uses `:request_id`.

| Type | Value | Hashed |
|---|---|---|
| `:request_id` | `context["request.id"]` | Never. It is already opaque. On USSD it is the telco session id, which rotates on timeout, so the session is ephemeral. |
| `:msisdn` | `context["request.msisdn"]` | Yes, when `hash_identifiers` is true (the default): SHA256, first 8 characters. |
| `:user_id` | `context["request.user_id"]` | Yes, when `hash_identifiers` is true. |

So with the default `hash_identifiers: true`, a phone number never appears in the session key in the clear, while a `request_id` passes through untouched.

### Worked examples

Default config, USSD, `RegistrationFlow`, no durable sessions. The identifier is `:request_id`, the telco session id, so the session lasts only as long as that telco session:

```
registration_flow:ussd:nalo:1699_telco_session_42
```

The same, but with `use_durable_sessions` (identifier `:user_id`, which Nalo sets equal to the msisdn) and hashing on. Now the user can time out and dial back into the same session:

```
registration_flow:ussd:nalo:a1b2c3d4
```

### Configuring sessions per processor

Set boundaries, identifier, and hashing directly:

```ruby
processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::CacheSessionStore
  config.use_session_config(boundaries: [:flow, :platform], identifier: :msisdn, hash_identifiers: true)
end
```

Or take full control of the id with a block:

```ruby
config.use_session_config do |context|
  "tenant:#{context["request.tenant_id"]}:#{context["request.msisdn"]}"
end
```

Three convenience methods wrap common changes:

| Method | Effect |
|---|---|
| `use_durable_sessions` | Sets the identifier to `:user_id`, a stable per-user id. It changes only the identifier, not the boundaries. It matters most on USSD, where `:request_id` rotates on timeout but `:user_id` (which Nalo sets equal to the msisdn) is stable, so the conversation survives a rotation. |
| `use_cross_platform_sessions` | Narrows boundaries to `[:flow]`, dropping platform and gateway, so one user shares a single session across platforms. |
| `use_url_isolation` | Appends `:url` to the current boundaries for per-tenant or per-host isolation. |

```ruby
processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::CacheSessionStore
  config.use_durable_sessions
end
```

One subtlety with `use_cross_platform_sessions`: dropping the `:platform` boundary only shares a session if the identifier resolves to the same value on both platforms. The platform default identifier differs (WhatsApp uses `:msisdn`, USSD uses `:request_id`), so for real cross-platform sharing pair it with a stable identifier, either `use_durable_sessions` (`:user_id`) or `identifier: :msisdn`.

## Async processing

Enable background processing with `use_async`. It has two forms:

```ruby
# Use a factory (no custom job class needed). The factory: keyword is required.
config.use_async(factory: :whatsapp)

# Or use your own ActiveJob subclass, with optional job params.
config.use_async(MyFlowJob, deployment_id: 123)
```

The webhook enqueues the job and returns immediately; the job re-runs the flow in the background. USSD does not support async, since its protocol needs a synchronous response. See [factory-pattern.md](factory-pattern.md) and [async-background-processing.md](async-background-processing.md).
