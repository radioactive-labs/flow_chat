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
- More than 3 render as a list.

The user's tap comes back as the choice key, so your flow reads `select` results the same way it does on every platform.

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

## Limits to keep in mind

| Area | Behavior on WhatsApp |
|---|---|
| Button titles | Reply-button titles are truncated to 20 characters. |
| List titles | List row titles are truncated to 24 characters; the full text is moved into the row description (up to 72 characters). |
| List size | A list section holds at most 10 rows; longer lists are split into multiple sections. |
| Media with choices | Passing `media:` together with more than 3 choices raises `ArgumentError`. |
| 24-hour window | WhatsApp only allows free-form messages within 24 hours of the user's last message. Outside that window you must send an approved template. FlowChat does not abstract this: `send_template` exists, but you manage templates and the window yourself. |

## Async

WhatsApp supports background processing. Acknowledge the webhook immediately and run the flow in a job with `use_async`. See [factory-pattern.md](../factory-pattern.md) and [async-background-processing.md](../async-background-processing.md).

## Related

- [Getting started](../getting-started.md)
- [Configuration](../configuration.md)
- [Instrumentation](../instrumentation.md)
