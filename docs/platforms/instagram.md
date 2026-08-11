# Instagram

The `FlowChat::Instagram::Gateway::SendApi` gateway integrates Instagram Direct Messages through the same Messenger Platform infrastructure Facebook Messenger uses: the Send API for outbound messages and the `entry[].messaging[]` webhook for inbound ones.

Meta offers two ways to reach Instagram messaging, and FlowChat implements one of them.

| | Instagram API with Instagram Login | Instagram API with Facebook Login |
|---|---|---|
| Linked Facebook Page | Not required | Required |
| Login flow | Business Login for Instagram | Facebook Login for Business |
| Access token | Instagram User token | Facebook User or Page token |
| Base URL | `graph.instagram.com` | `graph.facebook.com` |
| Account identifier | Instagram-scoped user id | Page-scoped user id |
| Supported here | No | Yes |

FlowChat models the **Facebook Login** path. The client posts to `graph.facebook.com`, authenticates with the Page access token, and matches an inbound delivery against the linked Page id rather than the Instagram account id. An Instagram professional account with no linked Facebook Page cannot be served by this gateway: supporting it would mean a different host, a different token type and a different account identifier, which is a separate integration rather than a configuration flag.

Instagram shares its webhook envelope and most of its rendering logic with Messenger (`FlowChat::Meta::MessagingGateway`), but has its own configuration, client and limits, and one crucial rendering difference: Instagram's interactive surfaces do not render everywhere, described below.

## Credentials

The gateway needs an access token, the linked Page id, and a verify token; an app secret is needed to validate webhook signatures. `instagram_account_id` is accepted and stored but not used by the gateway itself (account matching is against the linked Page id, see below); keep it around if your own code calls the Instagram Graph API directly.

```yaml
# config/credentials.yml.enc
instagram:
  access_token: "..."
  page_id: "..."                # the Facebook Page the Instagram account is linked to
  instagram_account_id: "..."   # informational; not used by the gateway
  verify_token: "..."           # your own value, echoed back during webhook setup
  app_id: "..."                 # used to classify echoes as :self, see below
  app_secret: "..."             # used to verify X-Hub-Signature-256
```

Equivalent environment variables: `INSTAGRAM_ACCESS_TOKEN`, `INSTAGRAM_PAGE_ID`, `INSTAGRAM_ACCOUNT_ID`, `INSTAGRAM_VERIFY_TOKEN`, `INSTAGRAM_APP_ID`, `INSTAGRAM_APP_SECRET`.

## Setup

```ruby
# app/controllers/instagram_controller.rb
class InstagramController < ApplicationController
  skip_forgery_protection

  def webhook
    processor = FlowChat::Processor.new(self) do |config|
      config.use_gateway FlowChat::Instagram::Gateway::SendApi
      config.use_session_store FlowChat::Session::CacheSessionStore
    end

    processor.run RegistrationFlow, :main_page
  end
end
```

```ruby
# config/routes.rb
match "/instagram/webhook", to: "instagram#webhook", via: [:get, :post]
```

Both verbs are needed: Meta sends a `GET` with `hub.mode=subscribe` to verify the endpoint (the gateway answers it using your `verify_token`), and `POST`s the actual events. Each `POST` is checked against `X-Hub-Signature-256` using the app secret; a request with a bad signature is answered `200 OK` without processing, so Meta stops retrying it.

With no second argument, `use_gateway` loads credentials through `FlowChat::Instagram::Configuration.from_credentials`, which reads the Rails credentials or environment variables above. That is the setup shown here.

### The webhook `object` field

Every delivery carries a top-level `object` field naming which subscription it came from. Messenger's is always `"page"`. Meta's own documentation is ambiguous about whether Instagram messaging events delivered via the Facebook Login path arrive under `"page"` or `"instagram"`, and this is not something FlowChat can settle for you: it depends on how your Meta app is configured. `FlowChat::Instagram::Gateway::SendApi#expected_webhook_object` defaults to `"instagram"`; confirm the real value against your app's dashboard, and override the method on a subclass if it disagrees. A delivery whose `object` does not match is dropped with `200 OK`, not an error, so a wrong value here fails silently rather than loudly.

### Webhook fields

As with Messenger, subscribe at least:

- `messages`: text, quick-reply taps, attachments, and message echoes.
- `messaging_postbacks`: carousel button taps.

Optionally, `message_deliveries` and `message_reads` surface as `MESSAGE_STATUS` events. Anything else you subscribe to arrives through `WEBHOOK_RECEIVED`, unmodelled, for your own code to interpret.

## Explicit and multi-account configuration

To run more than one linked account, or to load credentials from somewhere other than Rails credentials, build a `FlowChat::Instagram::Configuration` and pass it as the second argument to `use_gateway`.

```ruby
config = FlowChat::Instagram::Configuration.new(:support).tap do |c|
  c.access_token = tenant.instagram_access_token
  c.page_id = tenant.instagram_page_id
  c.verify_token = tenant.instagram_verify_token
  c.app_id = tenant.instagram_app_id
  c.app_secret = tenant.instagram_app_secret
end

processor = FlowChat::Processor.new(self) do |cfg|
  cfg.use_gateway FlowChat::Instagram::Gateway::SendApi, config
  cfg.use_session_store FlowChat::Session::CacheSessionStore
end
```

Passing a name to `new` registers the configuration under that name, so you can retrieve it later with `FlowChat::Instagram::Configuration.get(:support)`. For an unnamed configuration, use `FlowChat::Instagram::Configuration.new(nil)`. The configuration attributes are `access_token`, `page_id`, `instagram_account_id`, `verify_token`, `app_id`, `app_secret`, and `skip_signature_validation` (set it to `true` to bypass the `X-Hub-Signature-256` check, for local testing only).

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

`app.msisdn` is always `nil` on Instagram; there is no phone number in the IGSID Meta assigns a user. Use `app.user_id` (the IGSID) as the stable per-user identifier, which is also what sessions key on by default.

## How choices render

Instagram quick replies and the carousel (generic template) both render on the Instagram mobile app only, not on desktop or web. A user without the mobile app who reaches a screen with tappable-only options has no way to answer at all, so Instagram's renderer always lists the options as a numbered body as well as rendering the tappable surface, and a typed number is always accepted:

| Choices | Rendered as |
|---|---|
| 0 | Plain text, split at 1000 bytes UTF-8 |
| 1 to 13 | Quick replies, plus the same options numbered in the message body |
| 14 to 30 | A carousel, packed as postback buttons across generic-template cards, plus the same options numbered in the message body |
| 31 or more | Numbered text only; there is no tappable surface above 30 |

13 is Meta's cap on quick replies per message; 30 is 10 carousel elements times 3 buttons per element. A carousel card's title is not one of your choice labels: each card is titled "Options 1 to 3", "Options 4 to 6", and so on, describing which of the packed buttons it holds.

Tapping a quick reply or carousel button sends back the payload FlowChat generated for it; typing a number sends back its position. Because Instagram always shows both, both are live on the same turn, tracked as two separate mappings so a choice labelled `"1"` (whose generated payload is also `"1"`) cannot be confused with the first position.

## Media

Read inbound media through `app.media`, an Array of `FlowChat::Media`. Meta puts a direct, signed CDN URL on the attachment, so there is no separate media-id lookup step:

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

Instagram reports every message sent on a thread, including one typed by a human in the linked inbox and one sent by a different app connected to the same account, as a `message_echoes` event. FlowChat never lets an echo drive a flow (an echo of the bot's own send driving the flow again would loop), but it is published through the usual `WEBHOOK_RECEIVED` event, `field: "message_echoes"`, with a derived `echo_origin`:

| `echo_origin` | Meaning |
|---|---|
| `:self` | The echo's `app_id` matches this configuration's `app_id`. Our own send coming back. |
| `:other_app` | An `app_id` is present but does not match. Another connected app sent it. |
| `:human_agent` | No `app_id` at all. A person replying from the linked inbox. |

`:human_agent` is usually the signal an application wants: stand the flow down while a person is handling the conversation, and let it resume (or not) on your own logic.

## Who can be on each side

The account running the flow must be an Instagram **professional** account, Business or Creator, with a Facebook Page linked to it. A personal Instagram account cannot be the business side of a conversation: Meta's messaging API does not accept one, and there is no FlowChat setting that works around it.

The person on the other side is an ordinary Instagram user, which is the normal case and needs nothing from them.

Group threads are not supported. The webhook envelope pairs one sender with one recipient, and Meta does not expose group threads through this API.

## The user has to speak first

Meta only permits a send once the user has messaged the professional account: "only after an Instagram user has sent your app user's Instagram professional account a message can your app send a message to the Instagram user."

A flow therefore cannot open an Instagram conversation. There is no Instagram equivalent of an outbound-first WhatsApp template, so anything resembling a notification or a reminder has to begin with the user, or reach them on a platform that allows it. `FlowChat::Factory` and out-of-band sends through `context["instagram.client"]` are both bound by this: they can continue a conversation the user started, not start one.

## The 24-hour window

Separately from the rule above, Meta restricts free-form Instagram sends to within 24 hours of the user's last message, or to conversations opened with an approved message tag. FlowChat does not track this window or tag anything automatically. A send outside it is attempted like any other send: the Send API rejects it, the rejection is logged and reported through the standard API-error instrumentation, and the flow's turn otherwise proceeds as if the send had gone out. There is no retry and no automatic fallback to a template; both are the application's responsibility.

## Limits

| Area | Behavior on Instagram |
|---|---|
| Text length | Under 1000 bytes UTF-8 (measured in bytes, not characters, so multibyte text has a lower character budget), split into multiple messages above that |
| Quick replies | 13 per message, title truncated to 20 characters, mobile app only |
| Carousel | 10 elements, 3 postback buttons per element, button title truncated to 20 characters, mobile app only |
| Choice payload | Generated ids are capped at 1000 characters |
| Attachments | One per inbound message is read (the first); outbound is one attachment per send |
| 24-hour window | Not tracked by FlowChat; see above |

## Async

Instagram supports background processing with `use_async`. See [factory-pattern.md](../factory-pattern.md) and [async-background-processing.md](../async-background-processing.md).

## Related

- [Messenger](messenger.md)
- [Getting started](../getting-started.md)
- [Configuration](../configuration.md)
- [Instrumentation](../instrumentation.md)
