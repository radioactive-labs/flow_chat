# Messenger

The `FlowChat::Messenger::Gateway::SendApi` gateway integrates Facebook Messenger through Meta's Messenger Platform: the Send API for outbound messages and the `entry[].messaging[]` webhook for inbound ones. It handles webhook verification and signature checks, parses text, quick-reply taps, postbacks and attachments, and renders your flow's output as quick replies, a carousel, or plain numbered text depending on how many choices a screen offers.

Messenger and Instagram share this webhook envelope and most of their rendering logic (`FlowChat::Meta::MessagingGateway`), but each has its own configuration, client and limits, and a message meant for one is not deliverable through the other's credentials.

## Credentials

The gateway needs a Page access token, the Page id, and a verify token; an app secret is needed to validate webhook signatures.

```yaml
# config/credentials.yml.enc
messenger:
  access_token: "..."
  page_id: "..."
  verify_token: "..."          # your own value, echoed back during webhook setup
  app_id: "..."                # used to classify echoes as :self, see below
  app_secret: "..."            # used to verify X-Hub-Signature-256
```

Equivalent environment variables: `MESSENGER_ACCESS_TOKEN`, `MESSENGER_PAGE_ID`, `MESSENGER_VERIFY_TOKEN`, `MESSENGER_APP_ID`, `MESSENGER_APP_SECRET`.

## Setup

```ruby
# app/controllers/messenger_controller.rb
class MessengerController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Messenger::Gateway::SendApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run RegistrationFlow, :main_page
  end
end
```

```ruby
# config/routes.rb
match "/messenger/webhook", to: "messenger#webhook", via: [:get, :post]
```

Both verbs are needed: Meta sends a `GET` with `hub.mode=subscribe` to verify the endpoint (the gateway answers it using your `verify_token`), and `POST`s the actual events. Each `POST` is checked against `X-Hub-Signature-256` using the app secret; a request with a bad signature is answered `200 OK` without processing, so Meta stops retrying it.

With no second argument, `use_gateway` loads credentials through `FlowChat::Messenger::Configuration.from_credentials`, which reads the Rails credentials or environment variables above. That is the setup shown here.

### Webhook fields

Meta's Messenger webhook offers many subscribable fields; the gateway only models a few of them and publishes the rest as raw `WEBHOOK_RECEIVED` events (field name and value, unmodelled) rather than dropping them. Subscribe at least:

- `messages`: text, quick-reply taps, attachments, and message echoes.
- `messaging_postbacks`: carousel button taps, Get Started, ice breakers.

Optionally, `message_deliveries` and `message_reads` surface as `MESSAGE_STATUS` events. Anything else you subscribe to (`messaging_referrals`, `messaging_optins`, and so on) arrives through `WEBHOOK_RECEIVED` for your own code to interpret.

## Explicit and multi-page configuration

To run more than one Page, or to load credentials from somewhere other than Rails credentials, build a `FlowChat::Messenger::Configuration` and pass it as the second argument to `use_gateway`.

```ruby
config = FlowChat::Messenger::Configuration.new(:support).tap do |c|
  c.access_token = tenant.messenger_access_token
  c.page_id = tenant.messenger_page_id
  c.verify_token = tenant.messenger_verify_token
  c.app_id = tenant.messenger_app_id
  c.app_secret = tenant.messenger_app_secret
end

processor = FlowChat::Processor.new(self) do |cfg|
  cfg.use_gateway FlowChat::Messenger::Gateway::SendApi, config
  cfg.use_session_store FlowChat::Session::CacheSessionStore
end
```

Passing a name to `new` registers the configuration under that name, so you can retrieve it later with `FlowChat::Messenger::Configuration.get(:support)`. For an unnamed configuration, use `FlowChat::Messenger::Configuration.new(nil)`. The configuration attributes are `access_token`, `page_id`, `verify_token`, `app_id`, `app_secret`, and `skip_signature_validation` (set it to `true` to bypass the `X-Hub-Signature-256` check, for local testing only).

## The flow is the same

```ruby
class RegistrationFlow < FlowChat::Flow
  def main_page
    name = app.screen(:name) { |prompt| prompt.ask "What's your name?" }

    plan = app.screen(:plan) do |prompt|
      prompt.select "Choose a plan", { "basic" => "Basic", "pro" => "Pro" }
    end

    app.say "Welcome #{name}!"
  end
end
```

`app.msisdn` is always `nil` on Messenger; there is no phone number in the PSID Meta assigns a user. Use `app.user_id` (the PSID) as the stable per-user identifier, which is also what sessions key on by default.

## How choices render

The renderer picks a rung by choice count:

| Choices | Rendered as |
|---|---|
| 0 | Plain text, split into multiple messages above 2000 characters |
| 1 to 13 | Quick replies, one per choice |
| 14 to 30 | A carousel: choices packed as postback buttons across generic-template cards, 3 buttons per card |
| 31 or more | Plain text with the options numbered, `1.`, `2.`, and so on |

13 is Meta's cap on quick replies per message; 30 is 10 carousel elements times 3 buttons per element, Meta's caps on the generic template. Quick-reply titles are truncated to 20 characters; carousel button titles to 20 characters. A carousel card's title is not one of your choice labels: each card is titled "Options 1 to 3", "Options 4 to 6", and so on, describing which of the packed buttons it holds, because one option is one button rather than one option per card.

Above the carousel cap, or on a screen with more choices than fit one rung, a typed number resolves back to the original choice the same way a tap does. Tapping a quick reply or carousel button sends back the payload FlowChat generated for it; typing a number sends back its position. Both are accepted on any screen with choices, tracked as two separate mappings so a choice labelled `"1"` (whose generated payload is also `"1"`) cannot be confused with the first position.

## Media

Read inbound media through `app.media`, an Array of `FlowChat::Media`. Meta puts a direct, signed CDN URL on the attachment, so there is no separate media-id lookup step the way WhatsApp needs one:

```ruby
photo = app.media.first
if photo
  photo.type  # => :image
  bytes = photo.download
end
```

Signed CDN URLs expire; fetch `download` during the turn it arrives rather than from a session-stored answer later.

Send media outbound by passing `media:` to `ask` or `say`:

```ruby
app.say "Here is the map", media: { type: :image, url: "https://example.com/map.png" }
```

`upload_media` uploads a file for reuse and returns an attachment id you can pass as `media: { type: :image, id: attachment_id }` on a later send, avoiding a re-upload.

## Echoes and coexistence

Messenger reports every message sent on a thread, including one typed by a human in Page Inbox and one sent by a different app connected to the same Page, as a `message_echoes` event. FlowChat never lets an echo drive a flow (an echo of the bot's own send driving the flow again would loop), but it is published through the usual `WEBHOOK_RECEIVED` event, `field: "message_echoes"`, with a derived `echo_origin`:

| `echo_origin` | Meaning |
|---|---|
| `:self` | The echo's `app_id` matches this configuration's `app_id`. Our own send coming back. |
| `:other_app` | An `app_id` is present but does not match. Another connected app sent it. |
| `:human_agent` | No `app_id` at all. A person replying from Page Inbox. |

`:human_agent` is usually the signal an application wants: stand the flow down while a person is handling the conversation, and let it resume (or not) on your own logic.

## The 24-hour window

Meta restricts free-form Messenger sends to within 24 hours of the user's last message, or to conversations opened with an approved message tag. FlowChat does not track this window or tag anything automatically. A send outside it is attempted like any other send: the Send API rejects it, the rejection is logged and reported through the standard API-error instrumentation, and the flow's turn otherwise proceeds as if the send had gone out. There is no retry and no automatic fallback to a template; both are the application's responsibility.

## Limits

| Area | Behavior on Messenger |
|---|---|
| Text length | 2000 characters, split across multiple messages above that |
| Quick replies | 13 per message, title truncated to 20 characters |
| Carousel | 10 elements, 3 postback buttons per element, button title truncated to 20 characters |
| Choice payload | Generated ids are capped at 1000 characters |
| Attachments | One per inbound message is read (the first); outbound is one attachment per send |
| 24-hour window | Not tracked by FlowChat; see above |

## Async

Messenger supports background processing with `use_async`. See [factory-pattern.md](../factory-pattern.md) and [async-background-processing.md](../async-background-processing.md).

## Related

- [Instagram](instagram.md)
- [Getting started](../getting-started.md)
- [Configuration](../configuration.md)
- [Instrumentation](../instrumentation.md)
