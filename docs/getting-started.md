# Getting Started

This guide takes you from an empty Rails app to a running FlowChat flow. It reuses the same flow and processor shown in the [README](../README.md).

## Prerequisites

- A Rails application.
- Ruby 3.0 or newer.
- A cache the session store can use, such as `Rails.cache`.

## Install

Add the gem to your Gemfile:

```ruby
gem "flow_chat"
```

Then run `bundle install`. There are no migrations and no generators to run.

## Configure the cache

The cache-backed session store needs a cache. Set it once during boot, for example in an initializer:

```ruby
# config/initializers/flow_chat.rb
FlowChat::Config.cache = Rails.cache
```

Without a cache configured, `FlowChat::Session::CacheSessionStore` raises when it tries to read or write a session.

## Write your first flow

A flow is a class that inherits `FlowChat::Flow` and reads and writes the conversation through `app`. Each `app.screen` is one step:

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

FlowChat re-runs this method from the top on every webhook. Each `screen` returns its stored answer when the session already holds one, and re-prompts when it does not, so the method reads as a straight-line script even though each turn is a separate stateless request. For the mechanics, see [How the replay engine works](../README.md#how-the-replay-engine-works).

Put the flow anywhere Rails autoloads it, for example `app/flow_chat/registration_flow.rb`.

## Wire a controller

Build a processor in your webhook action, choose a gateway and session store, and run the flow. Here `self` is the controller:

```ruby
# app/controllers/ussd_controller.rb
class UssdController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Ussd::Gateway::Nalo
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run RegistrationFlow, :main_page
  end
end
```

`skip_forgery_protection` is needed because gateway webhooks are POSTs from an external service that cannot carry a Rails CSRF token. Point a route at the action:

```ruby
# config/routes.rb
post "/ussd", to: "ussd#webhook"
```

To run the same flow on another platform, change only `config.use_gateway`. The gateway classes and their platform symbols are listed in the [README](../README.md#wiring-a-platform).

## Try it in the simulator

FlowChat ships a web simulator for driving flows locally without a real gateway. It requires `FlowChat::Config.simulator_secret` to be set (for example in your initializer). Once set, you can step through a flow from the browser during development. See [testing.md](testing.md) for how to mount and use it.

## Next steps

- [configuration.md](configuration.md) for the full config surface and session options.
- [platforms/ussd.md](platforms/ussd.md), [platforms/whatsapp.md](platforms/whatsapp.md), and [platforms/telegram.md](platforms/telegram.md) for platform-specific behavior.
