# FlowChat

[![CI](https://github.com/radioactive-labs/flow_chat/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/radioactive-labs/flow_chat/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/flow_chat.svg)](https://badge.fury.io/rb/flow_chat)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.0-red.svg)](https://www.ruby-lang.org/)

**Write a conversation as an ordinary Ruby method. FlowChat runs it across stateless webhooks, on every messaging channel.**

A USSD or chat webhook is stateless: each message arrives as an isolated POST with no memory of the ones before it. The usual answer is a hand-rolled state machine: persist the current step, switch on it when the next message comes in, run the transition, persist the next step, repeat. FlowChat replaces that machine with a session and a replay engine, so you write the flow as a synchronous script that reads top to bottom.

```ruby
class RegistrationFlow < FlowChat::Flow
  def main_page
    name = app.screen(:name) { |prompt| prompt.ask "What's your name?" }

    email = app.screen(:email) do |prompt|
      prompt.ask "Your email?", validate: ->(input) { "Invalid email" unless input.include?("@") }
    end

    app.say "Welcome #{name}!"
  end
end
```

Each `screen` returns its stored answer when one exists and re-prompts when it does not. The method runs top to bottom on every turn and blocks on the first screen that has no answer yet. The same flow runs unchanged on USSD, WhatsApp, Telegram, and HTTP, with per-platform rendering.

## How the replay engine works

There is no saved program counter. On each webhook FlowChat rebuilds the app from the request and re-runs your flow method from the first line.

`app.screen(key)` is the fast-forward mechanism. When the session already holds a value for `key`, `screen` returns `session.get(key)` immediately and never yields. When it does not, `screen` yields a `FlowChat::Prompt`. If that prompt calls `ask` (or `select`, `yes?`) and no input is available yet, it raises `FlowChat::Interrupt::Prompt`. The interrupt unwinds the flow back to the Executor, which turns it into a rendered prompt and returns the response to the gateway.

The next webhook replays the same method from the top. Every screen that already has a stored answer is skipped in place. The screen that raised last time now sees the incoming input, runs its `validate` and `transform`, stores the accepted value with `session.set(key, value)`, and returns it, so execution falls through into the next screen. The flow advances one screen per turn without ever holding state between requests beyond the session hash.

Two rules follow from this design:

- One inbound message is consumed by one screen per turn. Once a screen takes the turn's input, later screens in the same run see no input and will prompt.
- A given screen key may be presented only once per run. Re-entering a key raises `ArgumentError`; use distinct keys or `app.go_back` to revisit.

## Installation

Add the gem to your Gemfile:

```ruby
gem "flow_chat"
```

Then run `bundle install`. FlowChat requires Ruby 3.0 or newer.

The cache-backed session store needs a cache. Set it once during boot, for example in an initializer:

```ruby
FlowChat::Config.cache = Rails.cache
```

Without a cache configured, `FlowChat::Session::CacheSessionStore` raises when it tries to read or write a session. There are no migrations and no generators to run.

## Wiring a platform

Build a processor, choose a gateway and session store, and run your flow:

```ruby
processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway FlowChat::Ussd::Gateway::Nalo
  config.use_session_store FlowChat::Session::CacheSessionStore
end

processor.run RegistrationFlow, :main_page
```

Point your controller's webhook action at this code (`self` is the controller). Each platform has its own gateway class:

| Platform | Gateway class | Platform symbol | Rendering |
|---|---|---|---|
| USSD | `FlowChat::Ussd::Gateway::Nalo` | `:ussd` | Numbered text menus, pagination, media as URL text |
| WhatsApp | `FlowChat::Whatsapp::Gateway::CloudApi` | `:whatsapp` | Reply buttons (<=3 choices), lists (>3), rich media |
| Telegram | `FlowChat::Telegram::Gateway::BotApi` | `:telegram` | Inline keyboards, rich media, HTML |
| HTTP | `FlowChat::Http::Gateway::Simple` | `:http` | JSON responses (testing, custom clients) |
| Intercom | `FlowChat::Intercom::Gateway::IntercomApi` | `:intercom` | Live-chat replies |

The same `RegistrationFlow` runs on any row by changing only `config.use_gateway`. To build a gateway for a platform not listed here, see [docs/gateway-development.md](docs/gateway-development.md).

## Building flows

A flow is a class that inherits `FlowChat::Flow` and reads and writes the conversation through `app`. Each unit of interaction is a screen:

```ruby
value = app.screen(:key) { |prompt| prompt.ask "..." }
```

The block receives a `FlowChat::Prompt`. Its methods:

| Method | Signature | Behavior |
|---|---|---|
| `ask` | `ask(msg, choices: nil, transform: nil, validate: nil, media: nil)` | Prompt for free input; validate, then transform, then return the value |
| `select` | `select(msg, choices, media: nil, error_message: "Invalid selection:")` | Prompt for one of `choices`; returns the chosen key |
| `yes?` | `yes?(msg)` | A `select` over Yes/No; returns `true` or `false` |
| `say` | `say(msg, media: nil)` | Send a terminal message and end the flow |

Details:

- `validate` is a callable that returns an error string when the input is rejected and `nil` when it passes. The received argument behaves like the input text (`input.include?("@")`, `input.to_i`, `input.strip`), and also exposes `media`, `location`, and `contact` for attachment-carrying turns.
- `transform` is a callable that maps the accepted input to the value `screen` stores and returns.
- `choices` may be an Array (`["Yes", "No"]`) or a Hash (`{ "1" => "Account", "2" => "Support" }`). With a Hash, `select` returns the key.
- Passing `media:` together with more than 3 `choices` raises `ArgumentError`. Use media or a longer choice list, not both.

`app.say` outside a block ends the flow from anywhere:

```ruby
def main_page
  confirmed = app.screen(:confirm) { |prompt| prompt.yes? "Place the order?" }
  app.say("Cancelled.") unless confirmed
  # ...
end
```

To send the user back to the previous screen, call `app.go_back`. It clears the current screen's stored answer and restarts the flow from the top, so the earlier screen prompts again. Remember that a screen key may appear only once per run: reuse of a key in a single pass raises `ArgumentError`.

## Media and rich input

An inbound turn is a `FlowChat::Input`. Read what the user sent through these accessors on `app`:

| Accessor | Returns |
|---|---|
| `app.text` | The message text (`""` when the turn carries only an attachment) |
| `app.media` | An Array of `FlowChat::Media` (empty array when none) |
| `app.location` | The shared location payload, or `nil` |
| `app.contact` | The shared contact card, or `nil` |
| `app.attachment_type` | `:media`, `:location`, `:contact`, or `nil` |

Reading an inbound photo:

```ruby
def main_page
  app.screen(:photo) do |prompt|
    prompt.ask "Send a photo of the receipt."
  end

  photo = app.media.first
  if photo
    photo.type       # => :image  (a Symbol; normalized across platforms)
    photo.mime_type  # => "image/jpeg"
    photo.caption    # => the caption text, or nil
    bytes = photo.download   # raw bytes, or nil on failure
    link  = photo.url        # a fetchable URL, or nil
  end
end
```

`app.media` is always an Array, so read a single item with `app.media.first` and check for `nil`; the type is a Symbol, read with `app.media.first&.type`. A caption-less photo still answers a screen: an attachment counts as submitted even when the text is blank.

To send media outbound, pass `media:` to `ask` or `say`:

```ruby
app.say "Here you go", media: { type: :image, url: "https://example.com/receipt.png" }
```

Caveat: a `Media` object that has been deserialized from a session store or a background job has lost its live platform client, so `url` and `download` return `nil`. If you need the bytes, call `download` eagerly in the same request that received the media, before the value round-trips through a session or job.

## Sessions

The default session boundaries are `[:flow, :gateway, :platform]`: a session is scoped to one flow, on one gateway, on one platform. Convenience methods adjust this:

| Method | Effect |
|---|---|
| `use_durable_sessions` | Key the session on a stable per-user identifier so it survives USSD session-id rotation across a conversation |
| `use_cross_platform_sessions` | Narrow the boundary to flow only, so one session is shared across platforms (for example USSD and WhatsApp) |
| `use_url_isolation` | Add a `:url` boundary for per-tenant or per-host isolation |
| `use_session_config(boundaries:, identifier:, hash_identifiers:, &block)` | Set boundaries, the identifier, and identifier hashing directly for full control |

```ruby
processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
  config.use_session_store FlowChat::Session::CacheSessionStore
  config.use_durable_sessions
end
```

See [docs/configuration.md](docs/configuration.md) for the full set of session options.

## Platform differences

The flow code is the same everywhere, but each platform imposes limits that the rendering respects and that you should keep in mind:

| Platform | Limits and behavior |
|---|---|
| USSD | Pages are split at 140 characters by default; media is rendered as a text line containing a URL, not an inline attachment; async processing is not available. |
| WhatsApp | Reply-button titles are truncated near 20 characters and list titles near 24; a list section holds at most 10 rows. WhatsApp's 24-hour customer-service window and its template requirement are not abstracted away: you manage message templates yourself. |
| Telegram | Choice taps arrive as callback queries; choices render as inline keyboards; message text supports HTML formatting. |
| HTTP | Requests and responses are JSON; each request must supply `session_id` and `user_id`. |

Platform guides: [docs/platforms/ussd.md](docs/platforms/ussd.md), [docs/platforms/whatsapp.md](docs/platforms/whatsapp.md), [docs/platforms/telegram.md](docs/platforms/telegram.md).

## Background processing

For platforms with an outbound API, you can acknowledge the webhook immediately and run the flow in a background job. Register a factory once, then call it from the webhook:

```ruby
# config/initializers/flow_chat.rb
FlowChat::Factory.register(:whatsapp) do |controller|
  processor = FlowChat::Processor.new(controller) do |config|
    config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
    config.use_session_store FlowChat::Session::CacheSessionStore
    config.use_async(factory: :whatsapp)
  end
  processor.run RegistrationFlow, :main_page
end

# app/controllers/whatsapp_controller.rb
def webhook
  FlowChat::Factory.execute(:whatsapp, controller: self)
end
```

The webhook enqueues `GenericAsyncJob` and returns; the job re-runs the same factory in the background, where the gateway detects the background context and processes the flow inline before sending the reply through the platform API. USSD does not support async, since it depends on a synchronous request-response cycle. See [docs/factory-pattern.md](docs/factory-pattern.md) and [docs/async-background-processing.md](docs/async-background-processing.md).

## Instrumentation

FlowChat emits `ActiveSupport::Notifications` events for flow execution, session lifecycle, and gateway activity. `FlowChat.metrics` collects counters over those events. See [docs/instrumentation.md](docs/instrumentation.md).

## Testing

FlowChat ships a web simulator for driving flows locally without a real gateway, useful during development. It requires `FlowChat::Config.simulator_secret` to be set. See [docs/testing.md](docs/testing.md).

## Development

Run the test suite with `rake test`. To run a single file, use `ruby -Itest test/unit/some_test.rb`. Architecture background is in [docs/architecture.md](docs/architecture.md) and [docs/getting-started.md](docs/getting-started.md).

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/radioactive-labs/flow_chat). Please add tests for behavior changes and keep them passing.

## License

FlowChat is released under the [MIT License](LICENSE.txt).
