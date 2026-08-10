# Facebook Messenger and Instagram DM Support: Design

**Date:** 2026-08-10
**Status:** Approved, not yet implemented
**Branch context:** builds on `feat/coexistence-webhooks`

## Problem

FlowChat ships gateways for USSD, WhatsApp, Telegram, HTTP and Intercom. Two Meta
messaging surfaces are missing: Facebook Messenger (Page DMs) and Instagram DMs.
Both run on the Messenger Platform, which shares an envelope and a Send API with
each other and shares webhook verification and signature validation with the
WhatsApp Cloud API gateway already in the tree.

Adding them by copying `lib/flow_chat/whatsapp/gateway/cloud_api.rb` would put a
third and fourth copy of the hub-verification and `X-Hub-Signature-256` logic in the
gem. That logic changed twice recently (`76b141b`, `f4fce7a`), so the copies would
drift.

## Goals

1. Facebook Messenger and Instagram DMs as first-class platforms, at parity with the
   WhatsApp gateway: gateway, configuration, client, renderer, choice mapping,
   inbound and outbound media, async, instrumentation, simulator, docs and tests.
2. One implementation of the Meta webhook plumbing, shared by all three Meta
   platforms.
3. Two correctness fixes to the WhatsApp gateway found while designing this.

## Non-Goals

- The handover protocol beyond publishing `standby` and `messaging_handovers`.
- Message tags for sends outside the 24 hour window.
- Persistent menus and ice breakers.
- The Instagram API with Instagram Login path (`graph.instagram.com`). Only the
  Facebook Login path is supported.
- Facebook Page feed or comment events. This is DMs only.

## Verified platform facts

Checked against Meta's documentation on 2026-08-10, because the rendering design
depends on the exact numbers.

| Surface | Messenger | Instagram |
|---|---|---|
| Quick replies | 13 max, title 20 chars, payload 1000 chars | 13 max, title 20 chars, mobile only, plain text only |
| Generic template (carousel) | 10 elements, 3 buttons per element, `postback` and `web_url` only, title 80, subtitle 80 | same, mobile app only, not on web |
| Text length | 2000 chars (NOT VERIFIED, the reference page did not render; confirm during implementation) | under 1000 chars, and 1000 bytes UTF-8 |
| Send endpoint | `POST /{PAGE_ID}/messages`, also `/me/messages` | same, and no `messaging_type` parameter |
| Rich text | none | none |

Webhook envelope for both: `object` at the top level, then `entry[].messaging[]`,
where each event carries `sender`, `recipient`, `timestamp` and one event-specific
key. Messenger delivers under `object: "page"`. Whether Instagram via Facebook Login
delivers under `page` or `instagram` was ambiguous in the docs, so the expected value
is a subclass hook to be confirmed against the app dashboard, not a constant baked
into shared code.

Messenger webhook fields: `messages`, `message_deliveries`, `message_echoes`,
`message_edits`, `message_reactions`, `message_reads`, `messaging_account_linking`,
`messaging_feedback`, `messaging_game_plays`, `messaging_handovers`,
`messaging_optins`, `messaging_policy_enforcement`, `messaging_postbacks`,
`messaging_referrals`, `messaging_seen`, `messenger_template_status_update`,
`response_feedback`, `send_cart`, `standby`.

WhatsApp interactive lists, for the fix below: "up to 10 sections, with up to 10 rows
for all sections combined", row title 24, row description 72, button text 20.

## Approach

A shared base with two thin gateways.

`FlowChat::Meta::` holds what all three Meta platforms share.
`FlowChat::Meta::MessagingGateway` implements the `entry[].messaging[]` envelope once.
`Messenger::Gateway::SendApi` and `Instagram::Gateway::SendApi` each subclass it and
override four hooks: platform symbol, configuration class, renderer class, and the
account-id check that corresponds to the `phone_number_id` comparison at
`cloud_api.rb:224`.

Instagram subclasses the shared base rather than the Messenger gateway. The two are
siblings, not parent and child, and making `Instagram` depend on the `Messenger`
namespace would misstate the relationship.

Rejected alternatives:

- **One gateway serving both platforms, branching on the webhook `object`.** Fewest
  files, and it mirrors how Meta frames the Messenger Platform, but the class would
  branch on platform for tokens, character limits, rendering capability and event
  types, and the configuration's `valid?` would depend on which half was configured.
- **Copy the WhatsApp gateway with a `platform:` constructor argument.** Cheapest to
  write and touches nothing existing, at the cost of a third and fourth copy of
  recently changed signature logic.

## Components

### 1. `FlowChat::Meta` (new)

- `lib/flow_chat/meta/webhook_verification.rb`: the `hub.mode` / `hub.verify_token` /
  `hub.challenge` exchange, including the empty-token guard from `cloud_api.rb:89`
  (a configuration with no verify token must verify nothing).
- `lib/flow_chat/meta/signature_validation.rb`: `X-Hub-Signature-256` HMAC over the
  raw body, using `FlowChat::Security.secure_compare`, with the
  `skip_signature_validation` escape and the "app_secret required" error.

`Whatsapp::Gateway::CloudApi` loses its private `handle_verification` and
`valid_webhook_signature?` and includes these instead. Behavior is unchanged, so
`test/unit/whatsapp/gateway/cloud_api_test.rb` is the regression net.

### 2. `FlowChat::NamedConfiguration` (new)

The named-configuration registry (`register`, `get`, `exists?`, `configuration_names`,
`clear_all!`, `register_as`) is currently duplicated verbatim in
`whatsapp/configuration.rb:46`, `telegram/configuration.rb:46` and
`intercom/configuration.rb:53`. The two new platforms would make five copies.

Extracted to one module, with **per-class storage**. The existing copies use a
`@@configurations` class variable; a shared module using `@@` would give every
platform one merged registry, which is a bug. The module keys storage per including
class instead.

All five classes migrate onto it. Telegram and Intercom have configuration test
suites. WhatsApp's configuration has no direct test, so its migration leans on the
gateway tests.

### 3. `Messenger::Configuration` and `Instagram::Configuration` (new)

`Messenger::Configuration` carries `page_id`, `access_token`, `verify_token`,
`app_id`, `app_secret`, `skip_signature_validation`. `Instagram::Configuration`
carries the same attributes, including `app_id` and `app_secret`, and adds
`instagram_account_id` alongside the linked `page_id`.

Both follow `whatsapp/configuration.rb:29`: a `from_credentials` reading `messenger:`
or `instagram:` from Rails credentials, falling back to `MESSENGER_*` or
`INSTAGRAM_*` environment variables. `valid?` requires access token, account id and
verify token.

`app_id` is load-bearing here, not decorative: it is what classifies echoes below.

`FlowChat::Config.messenger` and `FlowChat::Config.instagram` join
`FlowChat::Config.whatsapp`, each carrying `api_base_url` plus that platform's text
and choice limits as named constants rather than literals in the renderer.

### 4. Inbound: `Messenger::Gateway::SendApi` (new)

Walks `entry[].messaging[]` and dispatches on which key each event carries, following
the rule established by `27fd234`: model messaging, publish everything else.

| Event key | Treatment |
|---|---|
| `message` with `is_echo` | Published with a derived origin. Never drives a flow. |
| `message` | Drives the flow. Input from `text`, or `quick_reply.payload`, or the attachment caption. |
| `postback` | Drives the flow. Input from `payload`. Covers carousel buttons, Get Started and ice breakers. |
| `delivery`, `read` | `MESSAGE_STATUS`, mirroring `handle_statuses` at `cloud_api.rb:276`. |
| anything else | `WEBHOOK_RECEIVED` with the field name and the whole value. |

Two behaviors carry over from the WhatsApp gateway deliberately:

- The `flow_ran` single-flow guard (`cloud_api.rb:150`). Only one event per delivery
  can drive a flow, because only one can own the HTTP response.
- The ordering fix from `f17de9c`. Deliveries and reads are handled **before** the
  flow slot is claimed, so a receipt arriving ahead of a message in the same batch
  cannot spend the slot and drop the message.

Context values set:

| Key | Value |
|---|---|
| `request.id`, `request.user_id` | `sender.id`, the PSID or IGSID |
| `request.msisdn` | `nil`. Neither platform exposes a phone number. |
| `request.message_id` | `mid` |
| `request.platform` | `:messenger` or `:instagram` |
| `request.gateway` | `:messenger_send_api` or `:instagram_send_api` |
| `request.timestamp`, `request.body` | as WhatsApp sets them |
| `messenger.page.id` / `instagram.account.id` | the receiving account |
| `messenger.client` / `instagram.client` | the platform client, for out-of-band sends |
| `request.media` | attachments, normalized. `file` maps to `:document` to match the existing media contract. |

Inbound attachments are simpler than WhatsApp's. Meta puts a direct CDN URL in
`attachments[].payload.url`, so there is no media-id lookup step. Those URLs are
signed and expire, which the existing `Media` caveat about eager `download` already
covers.

### 5. Echoes and coexistence

An echo is not noise. `message_echoes` reports every message sent on the thread,
including replies typed by a human in Page Inbox and messages sent by another app.
An app needs that fact, typically to stop the bot while a human is handling the
conversation.

`app_id` distinguishes the cases, so the gateway derives `echo_origin` before
publishing:

| Condition | `echo_origin` |
|---|---|
| `app_id` equals the configured `app_id` | `:self` |
| `app_id` present and different | `:other_app` |
| `app_id` absent | `:human_agent` |

Published through the existing `WEBHOOK_RECEIVED` event with `field: "message_echoes"`
and the whole raw value, plus the derived `echo_origin`. This keeps one event
vocabulary and matches how WhatsApp publishes coexistence echoes, while sparing the
application from having to know Meta's `app_id` semantics.

Echoes never drive a flow. An echo of our own send that drove a flow would loop.

### 6. Outbound: clients

`Messenger::Client` and `Instagram::Client` expose
`send_message(recipient_id, text, choices:, media:)` and `upload_media`, wrapped in
the existing `report_delivery_failure` helper so `on_delivery_failure` and
`on_delivery_success` fire as they do at `cloud_api.rb:445`.

`platform_message_id_from` reads `result["message_id"]`. The Send API returns
`{recipient_id, message_id}`, flatter than WhatsApp's `messages[0].id`.

Sends outside the 24 hour messaging window are not modelled. The send is attempted,
and Meta's rejection travels the existing delivery-failure path like any other send
error. No window tracking and no automatic tagging: the gateway would be holding
state and guessing at policy the application owns.

### 7. Outbound: renderers and the choice ladder

Neither platform supports rich text, so a third text conversion is needed.
`Renderers::MarkdownSupport` currently offers `to_html` (used by Telegram) and
WhatsApp implements its own `to_whatsapp`. A shared `to_plain_text` is added to
`MarkdownSupport`: strip emphasis, render `ul` as bullets and `ol` as numbers, render
links as `text (url)`, decode entities.

The ladder:

| Choices | Messenger | Instagram |
|---|---|---|
| 0 | text, split at 2000 chars | text, split at 1000 bytes |
| 1 to 13 | quick replies, title 20, payload is the generated id | quick replies **and** a numbered list in the body |
| 14 to 30 | carousel, 10 elements by 3 postback buttons, element title 80, button title 20 | carousel **and** a numbered list in the body |
| above 30 | numbered list in the body, typed number accepted | same |

Instagram always carries the numbered list because both of its interactive surfaces
are mobile only. Without it, a user on desktop Instagram receives a prompt with no
selectable options and no way to answer, which is a dead-end turn. With it, mobile
users tap and desktop users type.

`Whatsapp::IdGenerator` is extracted to `FlowChat::IdGenerator` with a configurable
maximum length, since the quick-reply payload cap is 1000 rather than WhatsApp's 256.

### 8. Choice mapping

A `Middleware::ChoiceMapper` per platform, mapping payloads back to original choice
keys exactly as `whatsapp/middleware/choice_mapper.rb` does. Each gateway's
`configure_middleware_stack` inserts it, as `cloud_api.rb:56` does.

The mapper stores one mapping per turn whose keys depend on the rung the renderer
used. On the quick-reply and carousel rungs the keys are generated ids, as WhatsApp
does today. On the numbered rung the keys are the position strings `"1"`, `"2"` and
so on, following `Ussd::Middleware::ChoiceMapper`. Both resolve to the original choice
key, so the flow never sees the difference.

On Instagram, where the body carries a numbered list *and* quick replies or a
carousel, both key sets apply to the same turn. They are stored as **two separate
maps**, not merged into one, and resolved generated-id first with the position map as
the fallback.

Merging them would be a bug. `IdGenerator#normalize_label` keeps `\w`, which includes
digits, so a choice labelled `"1"` generates the id `"1"`. Given
`{"a" => "2", "b" => "1"}`, position `"1"` means choice `a` while generated id `"1"`
means choice `b`, and a single hash would silently lose one. Two maps with a defined
precedence make a tap and a typed number resolve independently and correctly.

### 9. Sessions

`platform_default_identifier` (`session/middleware.rb:93`) currently returns
`:msisdn` for `:whatsapp` and `:request_id` for everything else. Both new platforms
are added, returning `:user_id`, so sessions key on the PSID or IGSID explicitly
rather than relying on `request.id` happening to hold it.

### 10. Async, instrumentation, simulator

`GatewayAsyncSupport` is included in the base Messenger gateway, so Instagram
inherits it, and `async_supported?` stays true. The Factory pattern needs no changes,
so `GenericAsyncJob` covers both platforms unmodified.

No new instrumentation event constants. `MESSAGE_RECEIVED`, `MESSAGE_SENT`,
`MESSAGE_DELIVERY_FAILED`, `MESSAGE_STATUS`, `WEBHOOK_VERIFIED`, `WEBHOOK_FAILED` and
`WEBHOOK_RECEIVED` already carry `platform` and `gateway` in their payloads.

Both platforms are wired into the simulator, reusing the `simulator_mode` flag and
signed-cookie gating that `simulate?` (`cloud_api.rb:508`) implements.

`Messenger::ConfigurationError` and `Instagram::ConfigurationError` mirror
`Whatsapp::ConfigurationError`.

## WhatsApp fixes

Both found while designing the choice ladder, both in scope for this work.

### Fix 1: interactive lists above 10 choices are rejected

`Whatsapp::Renderer#build_list_message` (`renderer.rb:186`) slices more than 10
choices into multiple sections titled `1-10`, `11-20` and so on. Meta caps a list at
10 rows for all sections combined, so a 25-choice payload is rejected. The section
titles read like pagination, but nothing is paged: there is no second message and no
stored offset.

Corrected ladder, consistent with the new platforms:

| Choices | Rendering |
|---|---|
| 3 or fewer | interactive buttons, title truncated to 20 |
| 4 to 10 | interactive list, single section, title 24 and description 72 |
| above 10 | numbered list in the body, typed number accepted |

Row title and description truncation in the current code is already correct at 24 and
72, so only count handling changes. `test/unit/whatsapp/renderer_test.rb:209` asserts
the three-section payload and is rewritten to assert the fallback.

Paged list messages were considered and rejected for now. They work, but they need a
"More" row, a stored offset and a turn per page, and the numbered fallback gives all
four platforms one mechanism with no new state.

### Fix 2: WhatsApp echoes gain a derived origin

`handle_unmodelled_field` (`cloud_api.rb:309`) publishes coexistence echoes with the
raw value. It derives `echo_origin` the same way as above, so both platforms report a
human takeover identically.

## Testing

`test/unit/messenger/` and `test/unit/instagram/` mirroring `test/unit/whatsapp/`:
gateway, client, renderer, configuration, choice mapper. Plus
`test/integration/messenger_integration_test.rb` and the Instagram equivalent,
modelled on `whatsapp_integration_test.rb`.

Webhook fixtures covering: text, quick-reply reply, postback, attachment, self echo,
human-agent echo, delivery, read, and an unmodelled field.

Regression coverage for the shared extractions: existing WhatsApp gateway tests for
`Meta::` verification and signature validation, existing Telegram and Intercom
configuration tests for `NamedConfiguration`, `test/unit/whatsapp/id_generator_test.rb`
moved and extended for the configurable maximum length, and the rewritten WhatsApp
renderer test for the list fix.

## Implementation sequence

The work is large enough to want an order. Each phase leaves the tree green and is
reviewable on its own.

1. **Shared extractions and WhatsApp fixes.** `Meta::WebhookVerification`,
   `Meta::SignatureValidation`, `NamedConfiguration`, `FlowChat::IdGenerator`,
   `to_plain_text`, and both WhatsApp fixes. Touches only existing code and existing
   tests, and is independently valuable.
2. **Messenger.** `Meta::MessagingGateway` plus the Messenger configuration, client,
   renderer, choice mapper, gateway, session identifier, simulator, docs and tests.
3. **Instagram.** The subclass and its configuration, client and renderer, which is
   mostly limits and the always-numbered body, plus docs and tests.

Phase 1 landing first means phases 2 and 3 build on shared code that is already
proven by the existing suites rather than introducing it and its first consumer at
once.

## Documentation

New `docs/platforms/messenger.md` and `docs/platforms/instagram.md`. Updates to the
README platform table (`README.md:74`), the platform-differences table
(`README.md:186`), the intro sentence listing platforms (`README.md:26`) and the docs
index (`README.md:236`). `docs/gateway-context-variables.md` gains both gateways.

Docs follow the established register: dense plain prose, real limits and edge cases,
no marketing adjectives, no em-dashes.

## Open items for implementation

1. **Resolved, negatively.** Meta states no text limit for Messenger on any current
   reference page, unlike Instagram's documented 1,000 bytes. 2000 stays as the
   long-cited figure, with a comment recording that it is unverified. The client
   splits at this value rather than truncating, so being wrong low costs an extra
   message and being wrong high gets a send rejected.
2. Confirm whether Instagram via Facebook Login delivers webhooks under
   `object: "page"` or `object: "instagram"`, and set the subclass hook accordingly.
3. Confirm the Instagram carousel renders acceptably for plain option menus, since
   generic-template elements require a title per card and a menu has no natural card
   titles. If it reads badly, Instagram drops to the numbered list above 13 instead.
