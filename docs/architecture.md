# Architecture

FlowChat turns a stateless webhook into a stateful conversation by re-running your flow method from the top on every request and replaying its answers out of a session. This document explains the pieces that make that work.

## The middleware stack

A `FlowChat::Processor` builds one middleware stack per request, in a fixed order. Each layer wraps the next and calls it:

```
Gateway
  -> Session::Middleware
    -> platform middleware (and your custom middleware)
      -> Executor
        -> your Flow
```

The order is set in `Processor#create_middleware_stack`:

1. **Gateway** runs first. It parses the platform's webhook into normalized context values (`request.msisdn`, `context.input`, and so on) and, after the inner stack returns, renders the result back to the platform. See [gateway-development.md](gateway-development.md).
2. **`Session::Middleware`** computes the session id from the configured boundaries and identifier, and attaches the session store. See [configuration.md](configuration.md#sessions).
3. **Platform middleware** is inserted by the gateway if it defines `configure_middleware_stack`. USSD uses this to add pagination and choice-number mapping, and it is where your custom middleware runs. A gateway without that hook just runs your custom middleware here.
4. **Executor** runs last. Nothing runs after it. It instantiates your flow and calls the action.

## The Executor and control flow by exception

`FlowChat::Executor` builds a `FlowChat::App`, instantiates your flow with it, and calls the action method. Control flow is driven by exceptions raised from inside the flow and caught here:

```ruby
flow = flow_class.new(app)
flow.send(action)
raise FlowChat::Interrupt::Terminate, "Unexpected end of flow."
rescue FlowChat::Interrupt::RestartFlow
  retry
rescue FlowChat::Interrupt::Prompt => e
  [:prompt, e.prompt, e.choices, e.media]
rescue FlowChat::Interrupt::Terminate => e
  context.session.destroy
  [:terminal, e.prompt, nil, e.media]
```

The three interrupts live in `FlowChat::Interrupt`:

| Interrupt | Raised by | Effect |
|---|---|---|
| `Prompt` | `prompt.ask` / `select` / `yes?` when no input is available | Unwinds to the Executor, which returns the prompt for the gateway to render. Carries the message, choices, and media. |
| `Terminate` | `app.say` and `prompt.say` | Ends the flow, destroys the session, and returns a terminal message. |
| `RestartFlow` | `app.go_back` | Caught with `retry`, which re-runs the flow from the top against a fresh `App`. |

If the action method returns normally without prompting or terminating, the Executor raises `Terminate` with "Unexpected end of flow", since a flow is expected to either prompt for more input or end with a message.

These interrupts subclass `Exception`, not `StandardError`. This is deliberate: a `rescue` in your flow code (a bare `rescue => e` catches `StandardError`) will not swallow a prompt or terminate and break the engine. Avoid `rescue Exception` inside a flow, since that would catch them.

## The replay model

There is no saved program counter between requests. Each webhook rebuilds the `App` and re-runs the flow method from the first line. Progress is reconstructed from the session:

- `app.screen(key)` checks the session for `key`. If a value is stored, it returns immediately without yielding the block. This fast-forwards through every screen already answered.
- The first screen without a stored answer yields a `Prompt`. If the current turn has input for it, the prompt validates and transforms it, stores the result with `session.set(key, value)`, and returns, so execution falls through to the next screen. If not, the prompt raises `Interrupt::Prompt` and the turn ends there.

Two rules follow. One inbound message is consumed by one screen per turn: once a screen takes the input, later screens in the same run see no input and prompt. And a given screen key may be presented only once per run; re-entering a key raises `ArgumentError`. To revisit a screen, use `app.go_back`, which clears the current screen's answer and raises `RestartFlow`.

## The App

`FlowChat::App` is the single object your flow talks to. It wraps the context and exposes:

- `screen(key)`, the unit of interaction.
- `say(msg, media:)`, to end the flow.
- `go_back`, to return to the previous screen.
- Read accessors for the turn: `text`, `media`, `location`, `contact`, `attachment_type`, and identity values `msisdn`, `user_id`, `platform`, `gateway`, `message_id`, `timestamp`, `contact_name`.

`Flow` itself is a thin base class: it stores the `app` and nothing else. All conversation logic lives in the methods you write.

## Sessions

The session is a key-value store keyed by the session id. `FlowChat::Session::CacheSessionStore` persists it in `FlowChat::Config.cache`, so a session outlives the request. `screen` reads and writes it, `Terminate` destroys it. Boundaries and identifiers, which decide what shares a session, are covered in [configuration.md](configuration.md#sessions).

## Async

Gateways with an outbound API can run the flow in a background job instead of inline. The gateway detects async support, serializes the request, and enqueues a job that reconstructs a controller and re-runs the same stack in the background. USSD cannot do this, since its protocol needs a synchronous response. See [async-background-processing.md](async-background-processing.md) and [factory-pattern.md](factory-pattern.md).

## Instrumentation

Each stage emits `ActiveSupport::Notifications` events (flow execution, messages received and sent, session lifecycle, pagination, webhook verification). Subscribe to feed metrics and logs into your own backend. See [instrumentation.md](instrumentation.md).
