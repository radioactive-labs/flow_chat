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

The id is the configured boundary parts joined with the identifier. With the defaults, a WhatsApp user in `RegistrationFlow` gets a session scoped to that flow, on that gateway, on that platform, keyed by their (hashed) phone number. Change the boundaries to change the scope:

- `:flow` separates sessions per flow class.
- `:gateway` separates sessions per gateway (for example Nalo).
- `:platform` separates sessions per platform (`:ussd`, `:whatsapp`, and so on).
- `:url` separates sessions per host and path, useful for multi-tenant isolation.

The identifier is one of:

- `:request_id`, the gateway's per-request id. On USSD this rotates when the telco session times out, so a long conversation can lose its session.
- `:msisdn`, the user's phone number.
- `:user_id`, a stable per-user id that survives request and session-id rotation.

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
| `use_durable_sessions` | Sets the identifier to `:user_id`, a stable per-user id, so a session survives USSD session-id rotation across a conversation. |
| `use_cross_platform_sessions` | Narrows boundaries to `[:flow]`, so one user shares a single session across platforms (for example USSD and WhatsApp). |
| `use_url_isolation` | Appends `:url` to the current boundaries for per-tenant or per-host isolation. |

```ruby
processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::CacheSessionStore
  config.use_durable_sessions
end
```

## Async processing

Enable background processing with `use_async`. It has two forms:

```ruby
# Use a factory (no custom job class needed). The factory: keyword is required.
config.use_async(factory: :whatsapp)

# Or use your own ActiveJob subclass, with optional job params.
config.use_async(MyFlowJob, deployment_id: 123)
```

The webhook enqueues the job and returns immediately; the job re-runs the flow in the background. USSD does not support async, since its protocol needs a synchronous response. See [factory-pattern.md](factory-pattern.md) and [async-background-processing.md](async-background-processing.md).
