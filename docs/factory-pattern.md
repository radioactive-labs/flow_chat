# Factory pattern

A factory is a named block that builds and runs a processor. You register it once, then call it by name from both the webhook and the background job. This keeps the processor configuration in one place, so the two contexts cannot drift apart.

Without a factory, a webhook that enqueues a background job needs the same processor setup written twice: once in the controller and once in the job. A factory removes the duplication.

## Registering and executing

Register the factory in an initializer:

```ruby
# config/initializers/flow_chat.rb
FlowChat::Factory.register(:whatsapp) do |controller|
  processor = FlowChat::Processor.new(controller) do |config|
    config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
    config.use_session_store FlowChat::Session::CacheSessionStore
    config.use_async(factory: :whatsapp)
  end
  processor.run(WhatsAppFlow, :start)
end
```

Execute it from the webhook controller:

```ruby
# app/controllers/whatsapp_controller.rb
class WhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    FlowChat::Factory.execute(:whatsapp, controller: self)
  end
end
```

The block receives a controller and returns whatever `processor.run` returns. Executing an unregistered name raises `FlowChat::Factory::FactoryNotFoundError`.

## How it pairs with async

Notice the factory references itself: `config.use_async(factory: :whatsapp)`. That closes the loop.

1. The webhook calls `Factory.execute(:whatsapp, controller: self)`.
2. The factory builds a processor with `use_async(factory: :whatsapp)`, so the gateway enqueues `FlowChat::GenericAsyncJob` with `factory: :whatsapp` and returns immediately.
3. The background job calls `Factory.execute(:whatsapp, controller: background_controller)` again.
4. This time the gateway is running in the background, so it processes the flow inline and sends the reply.

The same factory builds the processor in both passes, so there is one definition of the gateway, session store, and flow. See [async-background-processing.md](async-background-processing.md) for what happens inside the job.

## Other methods

- `FlowChat::Factory.registered?(:whatsapp)` returns whether a name is registered.
- `FlowChat::Factory.registered_factories` lists the registered names.
- `FlowChat::Factory.clear!` removes all registrations (useful in tests).

## Related

- [Async and background processing](async-background-processing.md)
- [Configuration](configuration.md#async-processing)
