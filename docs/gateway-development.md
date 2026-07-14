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
