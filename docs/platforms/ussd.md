# USSD

USSD is the synchronous, text-only channel behind codes like `*123#`. The telco opens a session, sends each user entry to your webhook as a plain POST, and shows whatever text you return. FlowChat drives it with the same flows you write for every other platform, plus USSD-specific pagination and choice numbering.

FlowChat ships one USSD gateway: `FlowChat::Ussd::Gateway::Nalo`, for the [Nalo](https://nalosolutions.com) aggregator. Other aggregators are supported by writing a gateway (see [gateway-development.md](../gateway-development.md)).

## Setup

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

```ruby
# config/routes.rb
post "/ussd", to: "ussd#webhook"
```

The Nalo gateway reads `USERID`, `MSISDN`, and `USERDATA` from the request and renders a JSON response with `MSG` (the text to show) and `MSGTYPE` (`true` while the session continues, `false` when it ends). The phone number is normalized to E.164 and exposed as `app.msisdn`.

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

## Choice numbering

You define choices by their keys; FlowChat shows the user a numbered list and maps the number they type back to your key before the flow sees it. Your flow always works in keys, never in the displayed numbers.

```ruby
choice = app.screen(:menu) do |prompt|
  prompt.select "Main menu:", { "balance" => "Check balance", "airtime" => "Buy airtime" }
end
# The user sees "1. Check balance / 2. Buy airtime" and types 1 or 2.
# choice is "balance" or "airtime".
```

## Pagination

USSD messages are length-limited. When rendered output exceeds `FlowChat::Config.ussd.pagination_page_size` (140 characters by default), FlowChat splits it into pages at a word boundary and appends navigation options: `#` for "More" and `0` for "Back". It holds the paging state in the session and serves the next or previous page when the user sends the matching option, so a long menu or message spans several turns without any work in your flow. Tune the size and the option labels through [configuration.md](../configuration.md#ussd-configuration).

## Limits to keep in mind

| Area | Behavior on USSD |
|---|---|
| Message length | Output over 140 characters (default) is paginated into multiple turns. |
| Media | There is no inline media. Outbound `media:` is degraded to a text line with the media's URL, for example `Image: https://...`. |
| Rich choices | Choices render as a numbered text list, not buttons. |
| Async | Not supported. The USSD protocol needs a synchronous response, so `use_async` has no effect here. |
| Sessions | The telco's session id can rotate on timeout. Use `use_durable_sessions` to key the session on the phone number so a conversation survives a rotation. See [configuration.md](../configuration.md#sessions). |

## Related

- [Getting started](../getting-started.md)
- [Configuration](../configuration.md)
- [Building a gateway](../gateway-development.md)
