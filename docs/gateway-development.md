# Building a gateway

A gateway adapts one messaging platform to FlowChat. It is the first and last layer of the middleware stack: it parses the platform's inbound webhook into normalized context values on the way in, and renders the flow's output back to the platform on the way out. FlowChat ships gateways for USSD (Nalo), WhatsApp, Telegram, HTTP, and Intercom; write your own to support anything else.

## The contract

A gateway is a middleware object. It takes the next app in its constructor and implements `call(context)`:

```ruby
module MyCompany
  module Sms
    module Gateway
      class Twilio
        def initialize(app, config = nil)
          @app = app
          @config = config
        end

        def call(context)
          @context = context
          controller = context.controller
          params = controller.request.params

          # 1. Parse the inbound webhook into normalized context values.
          context["request.id"] = params["MessageSid"]
          context["request.msisdn"] = FlowChat::PhoneNumberUtil.to_e164(params["From"])
          context["request.user_id"] = context["request.msisdn"]
          context["request.message_id"] = SecureRandom.uuid
          context["request.timestamp"] = Time.current.iso8601
          context["request.gateway"] = :twilio
          context["request.platform"] = :sms
          context["request.body"] = params.to_h.transform_keys(&:to_s)
          context.input = params["Body"].presence || ""

          # 2. Run the rest of the stack. It returns [type, prompt, choices, media].
          type, prompt, choices, _media = @app.call(context)

          # 3. Render the result back to the platform.
          message = render(prompt, choices)
          send_sms(message, to: context["request.msisdn"])
        end

        private

        def render(prompt, choices)
          # Turn prompt + choices into whatever the platform expects.
        end

        def send_sms(message, to:)
          # Call the platform API.
        end
      end
    end
  end
end
```

`@app.call(context)` returns a four-element array: `[type, prompt, choices, media]`. `type` is `:prompt` while the conversation continues and `:terminal` when it has ended. `prompt` is the message text, `choices` is a hash of choice keys to labels (or `nil`), and `media` is an outbound media hash (or `nil`).

Use the gateway with `use_gateway`, passing any constructor arguments after the class:

```ruby
processor = FlowChat::Processor.new(self) do |config|
  config.use_gateway MyCompany::Sms::Gateway::Twilio, sms_config
  config.use_session_store FlowChat::Session::CacheSessionStore
end
```

## Context values to set

The session middleware and `FlowChat::App` read normalized keys off the context. Set the ones your platform can provide:

| Key | Purpose |
|---|---|
| `request.id` | The platform's session or conversation id. |
| `request.user_id` | A stable per-user id (used by `use_durable_sessions`). |
| `request.msisdn` | The user's phone number in E.164, when available. |
| `request.message_id` | A unique id for this message. |
| `request.timestamp` | ISO8601 time of the message. |
| `request.gateway` | Your gateway's symbol, for example `:twilio`. |
| `request.platform` | The platform symbol, for example `:sms`. |
| `request.body` | The raw request payload, with string keys. |
| `context.input` | The turn's text (a caption or `""` when the turn carries only an attachment). |
| `request.media` / `request.location` / `request.contact` | Structured attachments, when present. |

The full list and how each existing gateway populates it is in [gateway-context-variables.md](gateway-context-variables.md).

## Adding platform middleware

If your platform needs its own middleware (USSD adds pagination and choice-number mapping), define `self.configure_middleware_stack(builder, custom_middleware)`. The processor calls it in place of the default custom-middleware step, so you decide where your middleware and the user's sit:

```ruby
def self.configure_middleware_stack(builder, custom_middleware)
  builder.use MyCompany::Sms::Middleware::Segmentation
  builder.use custom_middleware
end
```

`custom_middleware` is the app's own custom-middleware builder. Include it, or the middleware a user added with `use_middleware` will not run.

## Writing a choice mapper

A choice mapper turns what the platform sends back into the key the flow branches on. Get one rule right and the rest follows:

> **Decide ambiguity under the same equivalence your resolver matches on.**

Every choice bug FlowChat has had came from breaking it — the resolver normalised input one way, and nothing checked whether two choices became indistinguishable under that normalisation, so one of them silently became unreachable.

`FlowChat::ChoiceTitles` enforces the rule for you. Pass it the `fold` your resolver applies and the `measure` your platform sizes fields in, and it hands back titles that are guaranteed distinct — numbering the whole set when they otherwise would not be:

```ruby
FlowChat::ChoiceTitles.build(choices, title_cap, measure: :characters)
# => [[key, original_label, displayed_title, was_truncated], ...]
```

Then make the displayed title the value you put on the wire. It is already unique within the set, so it needs no separate id space to be unique in — a tap sends it back as the payload, and a user who types what they read sends the same string, so one map resolves both.

**The best fold is no fold, and today no mapper uses one:**

| Mapper | Resolves on | Measure |
|---|---|---|
| WhatsApp, Messenger, Instagram | the displayed title, matched exactly | characters |
| Telegram | the displayed title, cut to `callback_data`'s limit | **bytes** |
| HTTP | the displayed title, matched exactly | characters |
| USSD, Intercom | the position printed beside each option | — |

USSD and Intercom are the strongest form of the rule: positions are unique whatever the labels say, so their equivalence relation is already injective and there is nothing to check. If your platform prints a number and asks for one, do that and you need none of this. Intercom used to match labels case-insensitively as well, and that is exactly what made two options reading the same collapse onto one entry — the number beside them was already doing that job unambiguously.

The rest match exactly, because a tapped payload and a client-echoed string are both produced by machines rather than typed. Every transform that could absorb a drift in those strings can also merge two choices, so none is worth adding on speculation. If you do add one — a platform where a person types freely might justify case folding — pass it as `fold:` so the ambiguity check uses it too, and expect more sets to be numbered as a result.

Where the number is already on screen — Intercom's numbered list, or the Meta `:numbered` rung — the mapper does not prefix anything, because the renderer is doing it. Prefixing in both places reads as `1. 1. Savings`.

Number the set rather than disambiguating with a suffix. A position prefix sits at the front and survives truncation from the right, which is what makes it work even on a platform as tight as Telegram's 64 bytes; a suffix is the first thing a cut removes.

## Supporting async

Include `FlowChat::GatewayAsyncSupport` to let the gateway run flows in a background job. The concern provides `should_enqueue_async?` (true when async is enabled, the gateway supports it, and the request is not already running in the background) and `enqueue_async_job` (serializes the request and enqueues the job). Override `async_supported?` to return `false` on a synchronous protocol:

```ruby
class Twilio
  include FlowChat::GatewayAsyncSupport

  def call(context)
    @context = context
    @controller = context.controller
    return if enqueue_async_job   # enqueued; respond immediately

    # ... otherwise process inline as above
  end
end
```

`enqueue_async_job` returns `false` when async should not be used (for example when the request is already the background job), so you fall through to inline processing. See [async-background-processing.md](async-background-processing.md).

## Related

- [Architecture](architecture.md)
- [Gateway context variables](gateway-context-variables.md)
- [Async and background processing](async-background-processing.md)
