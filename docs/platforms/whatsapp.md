# WhatsApp

The `FlowChat::Whatsapp::Gateway::CloudApi` gateway integrates the WhatsApp Business Cloud API. It handles Meta's webhook verification and signature checks, parses inbound messages (text, interactive replies, media, location, contacts), and renders your flow's output as WhatsApp interactive messages.

## Credentials

The gateway needs an access token, a phone number id, and a verify token; an app secret is needed to validate webhook signatures. Provide them through Rails credentials, environment variables, or a configuration object.

```yaml
# config/credentials.yml.enc
whatsapp:
  access_token: "..."
  phone_number_id: "..."
  verify_token: "..."          # your own value, echoed back during webhook setup
  app_secret: "..."            # used to verify X-Hub-Signature-256
```

Equivalent environment variables: `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_APP_SECRET`, `WHATSAPP_BUSINESS_ACCOUNT_ID`.

## Setup

```ruby
# app/controllers/whatsapp_controller.rb
class WhatsappController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run RegistrationFlow, :main_page
  end
end
```

```ruby
# config/routes.rb
match "/whatsapp/webhook", to: "whatsapp#webhook", via: [:get, :post]
```

Both verbs are needed: Meta sends a `GET` with `hub.mode=subscribe` to verify the endpoint (the gateway answers it using your `verify_token`), and `POST`s the actual messages. Each `POST` is checked against `X-Hub-Signature-256` using the app secret; a request with a bad signature is answered `200 OK` without processing, so Meta stops retrying it.

With no second argument, `use_gateway` loads credentials through `FlowChat::Whatsapp::Configuration.from_credentials`, which reads the Rails credentials or environment variables above. That is the setup shown here.

## Explicit and multi-tenant configuration

To run more than one WhatsApp number, or to load credentials from somewhere other than Rails credentials, build a `FlowChat::Whatsapp::Configuration` and pass it as the second argument to `use_gateway`.

```ruby
config = FlowChat::Whatsapp::Configuration.new(:support).tap do |c|
  c.access_token = tenant.whatsapp_access_token
  c.phone_number_id = tenant.whatsapp_phone_number_id
  c.verify_token = tenant.whatsapp_verify_token
  c.app_secret = tenant.whatsapp_app_secret
end

processor = FlowChat::Processor.new(self) do |cfg|
  cfg.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, config
  cfg.use_session_store FlowChat::Session::CacheSessionStore
end
```

Passing a name to `new` registers the configuration under that name, so you can retrieve it later with `FlowChat::Whatsapp::Configuration.get(:support)`. For an unnamed configuration, use `FlowChat::Whatsapp::Configuration.new(nil)`. The configuration attributes are `access_token`, `phone_number_id`, `verify_token`, `app_secret`, `business_account_id`, and `skip_signature_validation` (set it to `true` to bypass the `X-Hub-Signature-256` check, for local testing only).

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

## How choices render

FlowChat picks the WhatsApp interactive type from the number of choices:

- 3 choices or fewer render as reply buttons.
- 4 to 10 render as a list.
- Above 10 there is no interactive surface left: the options go straight into the message body, one per line, numbered.

Button and list row titles are only numbered when they need to be. FlowChat truncates each title to fit (20 characters for a button, 24 for a list row) and checks the whole set: if any title had to be truncated, or if two choices land on the same title, the titles as displayed can no longer identify a choice on their own. When that happens, every title in the set gets prefixed with its 1-based position ("1. ", "2. ", and so on), not just the ones that collided, so a stray "2." never appears next to a title with no "1." beside it. A short menu of distinct options (`Yes` / `No`) stays unprefixed; a menu with a long label, or with two choices sharing a label (two accounts both named "Savings"), gets every title numbered (`1. Yes` / `2. No`, `1. Transfer to savin...` / `2. Transfer to salar...`).

A user can reply by tapping, by typing the title exactly as shown, or - only when the screen was numbered - by typing the number. All of these resolve to the same choice key, so your flow reads `select` results the same way regardless of which one the user did. Above 10 choices, where nothing is tappable, the options go straight into the message body, one per line, always numbered, and a typed number is the only way to reply.

## Media

Read inbound media through `app.media`, an Array of `FlowChat::Media`:

```ruby
photo = app.media.first
if photo
  photo.type       # => :image
  photo.mime_type  # => "image/jpeg"
  bytes = photo.download
end
```

Send media outbound by passing `media:` to `ask` or `say`:

```ruby
app.say "Your receipt", media: { type: :document, url: "https://example.com/receipt.pdf" }
```

The WhatsApp client also exposes direct senders (`send_image`, `send_document`, `send_audio`, `send_video`, `send_sticker`, `send_template`) and `upload_media`, which uploads a file and returns a media id you can reuse.

Media and choices combine, but media never changes which choice surface renders. 3 choices or fewer is the one case WhatsApp can carry both in a single message: the media becomes the header on the reply buttons.

```ruby
app.screen(:plan) do |prompt|
  prompt.select "Choose a plan", { "basic" => "Basic", "pro" => "Pro" },
    media: { type: :image, url: "https://example.com/plans.png" }
end
```

From 4 to 10 choices there is no interactive surface left that can carry media: Meta's interactive message reference documents a `text`-only header for list messages, image and video and document headers are only defined for button messages. So the image goes out as its own message first, with no caption (the question is about to appear in the list body right behind it), followed by the list exactly as it would render with no media at all.

Above 10 choices the options are already nothing but text, and a WhatsApp media message can carry a caption up to 1024 characters (documented for image, video, and document messages; audio and sticker messages have no caption field at all). When the media type supports a caption and the prompt plus the numbered options fit under that cap, FlowChat sends one message: the media with the whole numbered list as its caption. When either does not hold - a long option list, or an audio or sticker attachment - it falls back to the same two-message shape as the list rung: the media on its own, with no caption, followed by the numbered text.

## Limits to keep in mind

| Area | Behavior on WhatsApp |
|---|---|
| Button titles | Reply-button titles are truncated to 20 characters. |
| List titles | List row titles are truncated to 24 characters; the full text is moved into the row description (up to 72 characters). |
| List size | A list section holds at most 10 rows; longer lists are split into multiple sections. |
| Media with choices | 3 or fewer: one message, buttons with a media header. 4 to 10: media sent separately, then the list. Above 10: one captioned media message when the caption fits under 1024 characters and the media type supports a caption (image, video, document), otherwise media sent separately, then the numbered text. Never more than 3 reply buttons, with or without media. |
| 24-hour window | WhatsApp only allows free-form messages within 24 hours of the user's last message. Outside that window you must send an approved template. FlowChat does not abstract this: `send_template` exists, but you manage templates and the window yourself. |

## Async

WhatsApp supports background processing. Acknowledge the webhook immediately and run the flow in a job with `use_async`. See [factory-pattern.md](../factory-pattern.md) and [async-background-processing.md](../async-background-processing.md).

## Related

- [Getting started](../getting-started.md)
- [Configuration](../configuration.md)
- [Instrumentation](../instrumentation.md)
