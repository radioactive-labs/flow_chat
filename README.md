# FlowChat

FlowChat is a Rails framework designed for crafting Menu-based conversation workflows, such as those used in USSD systems. It introduces an intuitive approach to defining conversation flows in Ruby, facilitating clear and logical flow development. Currently supporting USSD with plans to extend functionality to WhatsApp and Telegram, FlowChat makes multi-channel user interaction seamless and efficient.

The framework's architecture leverages a middleware processing pipeline, offering flexibility in customizing the conversation handling process.

## Getting Started

### Installation

Incorporate FlowChat into your Rails project by adding the following line to your Gemfile:

```ruby
gem 'flow_chat', '~> 0.2.0'
```

Then, execute:

```bash
bundle install
```

Alternatively, you can install it directly using:

```bash
gem install flow_chat
```

### Basic Usage

#### Building Your First Flow

Create a new class derived from `FlowChat::Flow` to define your conversation flow. It's recommended to place your flow definitions under `app/flow_chat`.

For a simple "Hello World" flow:

```ruby
class HelloWorldFlow < FlowChat::Flow
  def main_page
    app.say "Hello World!"
  end
end
```

The `app` instance within `FlowChat::Flow` provides methods to interact with and respond to the user, such as `app.say`, which sends a message to the user.

#### Integration with USSD

Given that most USSD gateways interact via HTTP, set up a controller to handle the conversation flow:

```ruby
class UssdDemoController < ApplicationController
  skip_forgery_protection

  def hello_world
    ussd_processor.run HelloWorldFlow, :main_page
  end

  private

  def ussd_processor
    @ussd_processor ||= FlowChat::Ussd::Processor.new(self) do |processor|
      processor.use_gateway FlowChat::Ussd::Gateway::Nalo
      processor.use_session_store FlowChat::Session::RailsSessionStore
    end
  end
end
```

This controller initializes a `FlowChat::Ussd::Processor` specifying the use of Nalo Solutions' gateway and a session storage mechanism. Here, `RailsSessionStore` is chosen for simplicity and demonstration purposes.

Bind the controller action to a route:

```ruby
Rails.application.routes.draw do
  post 'ussd_hello_world' => 'ussd_demo#hello_world'
end
```

#### Testing with the USSD Simulator

FlowChat comes with a USSD simulator for local testing:

```ruby
class UssdSimulatorController < ApplicationController
  include FlowChat::Ussd::Simulator::Controller

  protected

  def default_endpoint
    '/ussd_hello_world'
  end

  def default_provider
    :nalo
  end
end
```

And set up the corresponding route:

```ruby
Rails.application.routes.draw do
  get 'ussd_simulator' => 'ussd_simulator#ussd_simulator'
end
```

Visit [http://localhost:3000/ussd_simulator](http://localhost:3000/ussd_simulator) to initiate and test your flow.

### Advanced Usage: Implementing Multiple Screens

To engage users with a multi-step interaction, define a flow with multiple screens:

```ruby
class MultipleScreensFlow < FlowChat::Flow
  def main_page
    name = app.screen(:name) { |prompt|
      prompt.ask "What is your name?", transform: ->(input) { input.squish }
    }

    age = app.screen(:age) do |prompt|
      prompt.ask "How old are you?",
        convert: ->(input) { input.to_i },
        validate: ->(input) { "You must be at least 13 years old" unless input >= 13 }
    end

    gender = app.screen(:gender) { |prompt| prompt.select "What is your gender", ["Male", "Female"] }

    confirm = app.screen(:confirm) do |prompt|
      prompt.yes?("Is this correct?\n\nName: #{name}\nAge: #{age}\nGender: #{gender}")
    end

    app.say confirm ? "Thank you for confirming" : "Please try again"
  end
end
```

This example illustrates a flow that collects and confirms user information across multiple interaction steps, showcasing FlowChat's capability to handle complex conversation logic effortlessly.

TODO:

### Sub Flows

TODO:

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/flow_chat.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
