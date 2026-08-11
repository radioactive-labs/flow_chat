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

13 is Meta's cap on quick replies per message; 30 is 10 carousel elements times 3 buttons per element. A carousel card's own title is not one of your choice labels: each card is titled "Options 1 to 3", "Options 4 to 6", and so on, describing which of the packed buttons it holds.

The numbered body and the numbering on a quick-reply or carousel button title are two separate things that happen to usually appear together. The body is always numbered, on every rung, because a desktop user with no tappable surface at all still needs a way to answer. The button's own title, by contrast, is only prefixed with a position when it needs to be: FlowChat truncates each title to fit (20 characters) and checks the whole set, and if any title had to be truncated, or if two choices land on the same title, every title in the set gets prefixed, not just the ones that collided. A short menu of distinct options (`Yes` / `No`) has an unprefixed title even though the body right next to it still reads "1. Yes\n2. No"; a menu with a long label, or with two choices sharing a label, gets both the title and the body numbered. This is decided across the whole choice set, not per carousel card, the same as on Messenger.

A user can reply to any screen with choices by tapping, by typing the title exactly as shown, or by typing the position number - the number always works here, because the body always shows one, even on an unprefixed screen. Tapping sends back the payload FlowChat generated for the button; typing the title sends back that exact string; typing the number sends back its position. These are tracked as three separate mappings, resolved in that order (payload, then title, then position), so a choice labelled `"1"` (whose generated payload is also `"1"`) cannot be confused with the first position. Above 30 choices, where there is no tappable surface, the number in the body is the only way to reply.

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

Media and choices combine: pass both `media:` and `choices:` to `ask` or `say` and you get both, not one or the other. Media does not change which choice surface renders - it is additive, sent as its own message ahead of whichever quick replies, carousel, or numbered text the choice count would render with no media at all. Instagram's always-numbered body still applies on top: a mobile user gets the image, then tappable quick replies (or a carousel) with the options numbered in the body next to them, and a desktop user gets the image, then the numbered body with nothing tappable, same as with no media at all.

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

Separately from the rule above, Meta restricts free-form Instagram sends to within 24 hours of the user's last message, or to conversations opened with an approved message tag. FlowChat does not track this window automatically, but it does carry a tag when you ask it to. Pass `tag:` to `context["instagram.client"]`'s `send_message` or `send_text`:

```ruby
context["instagram.client"].send_message(igsid, "Following up on your case", tag: "HUMAN_AGENT")
```

`HUMAN_AGENT` is the only tag Meta still accepts as of 27 April 2026, and it extends the window to 7 days for human-agent support; it needs the Human Agent app feature approved on your app first. FlowChat passes whatever you give it straight through to the Send API without checking it against a list, since Meta already refuses an unknown tag clearly (error 100) and an allowlist here would be one more thing to keep in sync with Meta's own set. Deciding when a send qualifies for the tag is the application's job.

Instagram's client never sends `messaging_type` on an untagged send, since Meta's Instagram reference does not document that field at all. A tagged send is the exception: Meta does document `MESSAGE_TAG` with `HUMAN_AGENT` for Instagram, so a tagged send sets `messaging_type: "MESSAGE_TAG"` and `tag: "HUMAN_AGENT"` even though nothing else here ever sets `messaging_type`. When a reply is long enough to split, or carries media alongside choices and so goes out as more than one message, every part carries the same tag.

A send outside the window with no tag is attempted like any other send: the Send API rejects it, the rejection is logged and reported through the standard API-error instrumentation, and the flow's turn otherwise proceeds as if the send had gone out. There is no retry and no automatic fallback to a template; both are the application's responsibility.

## Limits

| Area | Behavior on Instagram |
|---|---|
| Text length | Under 1000 bytes UTF-8 (measured in bytes, not characters, so multibyte text has a lower character budget), split into multiple messages above that |
| Quick replies | 13 per message, title truncated to 20 characters, mobile app only |
| Carousel | 10 elements, 3 postback buttons per element, button title truncated to 20 characters, mobile app only |
| Choice payload | Generated ids are capped at 1000 characters |
| Attachments | One per inbound message is read (the first); outbound is one attachment per send |
| Media with choices | Sent as its own message ahead of the choice message; does not change which rung renders |
| 24-hour window | Not tracked automatically; `tag:` is passed through unvalidated, see above |

## Async

Instagram supports background processing with `use_async`. See [factory-pattern.md](../factory-pattern.md) and [async-background-processing.md](../async-background-processing.md).

## Related

- [Messenger](messenger.md)
- [Getting started](../getting-started.md)
- [Configuration](../configuration.md)
- [Instrumentation](../instrumentation.md)
