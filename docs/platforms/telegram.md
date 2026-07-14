# Telegram

The `FlowChat::Telegram::Gateway::BotApi` gateway integrates the Telegram Bot API. It parses inbound messages and callback queries, renders choices as inline keyboards, formats text as Telegram HTML, and sends media through the Bot API.

## Credentials

The gateway needs a bot token from [@BotFather](https://t.me/BotFather). A secret token is optional but recommended: Telegram sends it back in the `X-Telegram-Bot-Api-Secret-Token` header on every webhook, and the gateway rejects requests whose token does not match.

```yaml
# config/credentials.yml.enc
telegram:
  bot_token: "123456:ABC-DEF..."
  secret_token: "..."          # optional; validates incoming webhooks
```

Equivalent environment variables: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_SECRET_TOKEN`.

## Setup

```ruby
# app/controllers/telegram_controller.rb
class TelegramController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Telegram::Gateway::BotApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run RegistrationFlow, :main_page
  end
end
```

```ruby
# config/routes.rb
post "/telegram/webhook", to: "telegram#webhook"
```

Telegram delivers updates by `POST`. Register your webhook URL with the Bot API's `setWebhook` method, passing the same `secret_token` you configured so Telegram includes it on each request. Pass a named configuration object as the second argument to `use_gateway` to run more than one bot.

## The flow is the same

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

## Callback queries and inline keyboards

Choices render as an inline keyboard: buttons attached under the message. When the user taps one, Telegram sends a `callback_query` rather than a text message. The gateway uses the button's data as the input and answers the query automatically to clear the loading spinner, so your `select` returns the choice key exactly as on other platforms.

```ruby
choice = app.screen(:menu) do |prompt|
  prompt.select "Main menu:", { "balance" => "Check balance", "airtime" => "Buy airtime" }
end
```

Buttons are laid out two per row for up to four choices, and one per row beyond that. Button text is truncated to 64 characters, the Bot API's limit.

## Formatting and media

Message text is rendered as Telegram HTML, so Markdown in your prompts becomes bold, italic, links, and code. Read inbound media through `app.media` and send media outbound with `media:`, the same as other platforms:

```ruby
app.say "Here is the map", media: { type: :photo, url: "https://example.com/map.png" }
```

Telegram media types include photo, document, video, audio, and voice; FlowChat normalizes `:photo` to `:image` and `:voice` to `:audio` on inbound `Media` so `media.type` is consistent across platforms.

## Async

Telegram supports background processing with `use_async`. See [factory-pattern.md](../factory-pattern.md) and [async-background-processing.md](../async-background-processing.md).

## Related

- [Getting started](../getting-started.md)
- [Configuration](../configuration.md)
- [Instrumentation](../instrumentation.md)
