# Testing

FlowChat gives you two ways to exercise a flow without a live gateway: a web simulator for manual, interactive testing during development, and the HTTP gateway for automated request tests.

## The simulator

The simulator is a web page that drives your flows the way a real platform would, so you can step through a conversation from the browser. It works the same regardless of which gateway a flow targets.

Enable it in two steps.

Set the simulator secret during boot:

```ruby
# config/initializers/flow_chat.rb
FlowChat::Config.simulator_secret = Rails.application.credentials.flow_chat_simulator_secret
```

The secret gates access. The simulator controller signs a cookie with it, and the gateways only enter simulator mode when that cookie is valid, so the simulator stays off in any environment where the secret is unset.

Mount a controller that includes the simulator module and lists the endpoints to test:

```ruby
# app/controllers/simulator_controller.rb
class SimulatorController < ApplicationController
  include FlowChat::Simulator::Controller

  def index
    flowchat_simulator
  end

  protected

  def configurations
    {
      ussd_main: {
        name: "USSD",
        processor_type: "ussd",
        gateway: "nalo",
        endpoint: "/ussd"
      },
      whatsapp_main: {
        name: "WhatsApp",
        processor_type: "whatsapp",
        gateway: "cloud_api",
        endpoint: "/whatsapp/webhook"
      }
    }
  end
end
```

```ruby
# config/routes.rb
get "/simulator", to: "simulator#index"
```

Each entry in `configurations` points at one of your real webhook endpoints, so the simulator posts to the same controller actions the platform would. Open `/simulator`, pick an endpoint, and send messages.

## Automated tests

For request specs, drive a flow through the HTTP gateway (`FlowChat::Http::Gateway::Simple`), which speaks plain JSON. Point a controller at your flow:

```ruby
class ChatController < ApplicationController
  def webhook
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Http::Gateway::Simple
      config.use_session_store FlowChat::Session::CacheSessionStore
    end
    processor.run RegistrationFlow, :main_page
  end
end
```

The Simple gateway expects `session_id` and `user_id` in the request and returns JSON with the prompt, choices, and any media. Post the next input with the same `session_id` to advance the conversation, and assert on the returned message and choices. Set `FlowChat::Config.cache` to a real store (for example `ActiveSupport::Cache::MemoryStore.new`) in your test setup so sessions persist across the requests in a single test.

Because one flow behaves the same across platforms, a flow verified through the HTTP gateway behaves the same on USSD, WhatsApp, and Telegram, apart from each platform's rendering.

## Related

- [Getting started](getting-started.md)
- [Configuration](configuration.md)
