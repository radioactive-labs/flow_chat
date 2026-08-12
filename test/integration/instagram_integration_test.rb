require "test_helper"
require_relative "../support/test_helpers"

class InstagramIntegrationTest < Minitest::Test
  include FlowChat::TestSupport::TestHelpers

  class RegistrationFlow < FlowChat::Flow
    def main_page
      name = app.screen(:name) { |prompt| prompt.ask "What is your name?" }
      plan = app.screen(:plan) do |prompt|
        prompt.select "Choose a plan", {"basic" => "Basic", "pro" => "Pro"}
      end
      app.say "Thanks #{name}, you chose #{plan}."
    end
  end

  # 25 normal-length options is the exact shape from the reported repro: it
  # lands on the carousel rung (capacity is 10 elements * 3 buttons = 30),
  # and Instagram's always_number? forces every option into the message body
  # too, which is what pushed that body past Instagram's 1000-byte cap
  # before Client#deliver split :carousel bodies (Blocker 2). Media riding
  # alongside 25 choices additionally exercises Blocker 1: the old guard
  # made this whole scenario impossible to reach from a flow at all.
  class MediaCarouselFlow < FlowChat::Flow
    def main_page
      choice = app.screen(:choice) do |prompt|
        choices = (1..25).to_h { |i| ["opt#{i}", "This is a normal length menu option label #{i}"] }
        prompt.select "Pick one from the following menu", choices, media: {type: :image, url: "https://example.com/menu.png"}
      end
      app.say "You picked #{choice}."
    end
  end

  # Same Blocker 3 shape as MessengerIntegrationTest's ArrayMenuThenPinFlow:
  # Array choices make key == label, so the generated id/position can
  # collide with the resolved value and defeat a staleness check that asks
  # about the resolved value instead of the original one. Instagram's
  # ChoiceMapper is a subclass of Messenger's, sharing this exact code path.
  class ArrayMenuThenPinFlow < FlowChat::Flow
    def main_page
      choice = app.screen(:choice) do |prompt|
        prompt.select "Choose one", [
          "A very long label that gets truncated for sure",
          "Another very long label here for sure too"
        ]
      end
      pin = app.screen(:pin) { |prompt| prompt.ask "Enter your PIN:" }
      app.say "You picked #{choice} and entered PIN #{pin}."
    end
  end

  def setup
    @config = FlowChat::Instagram::Configuration.new(nil)
    # A page-linked account: the page is what a send is addressed to, the
    # account is what an inbound delivery names.
    @config.page_id = "page_1"
    @config.instagram_account_id = "ig_1"
    @config.access_token = "tok"
    @config.verify_token = "verify"
    @config.skip_signature_validation = true

    # processor.gateway is not exposed by FlowChat::Processor (it only keeps
    # @gateway_class/@gateway_args privately, see lib/flow_chat/processor.rb),
    # so there is no built gateway/client instance to reach into after the
    # processor runs. Messenger's own integration test patches
    # Client#send_message at the class level, but Instagram always numbers
    # the options into the message body inside the renderer, which
    # send_message calls internally, so patching that high up would skip
    # the very rendering this test needs to see. Patching #post_message
    # instead (defined on Messenger::Client, inherited here) lets the real
    # render and deliver logic run and stops the chain one step before the
    # network call.
    @sent = []
    sent = @sent
    @original_post_message = FlowChat::Instagram::Client.instance_method(:post_message)
    FlowChat::Instagram::Client.define_method(:post_message) do |recipient_id, message, tag|
      sent << {to: recipient_id, message: message, tag: tag}
      {"recipient_id" => recipient_id, "message_id" => "mid.#{sent.length}"}
    end
  end

  def teardown
    FlowChat::Instagram::Client.define_method(:post_message, @original_post_message)
  end

  def test_tapped_quick_reply_advances_the_flow
    session_data = {}

    run_webhook(text: "Hello", session_data: session_data)
    assert_match(/What is your name/, last_sent_prompt)

    run_webhook(text: "Ama", session_data: session_data)
    assert_match(/Choose a plan/, last_sent_prompt)
    assert_match(/1\. Basic/, last_sent_prompt)

    tapped = last_sent_quick_reply_payload
    run_webhook(quick_reply: tapped, session_data: session_data)
    assert_match(/Thanks Ama/, last_sent_prompt)
  end

  # The desktop path: Instagram quick replies and carousels are mobile-only,
  # so the renderer always numbers the options in the body, and a typed digit
  # must resolve just as a tap would.
  def test_typed_number_advances_the_flow
    session_data = {}

    run_webhook(text: "Hello", session_data: session_data)
    assert_match(/What is your name/, last_sent_prompt)

    run_webhook(text: "Ama", session_data: session_data)
    assert_match(/Choose a plan/, last_sent_prompt)
    assert_match(/1\. Basic/, last_sent_prompt)

    run_webhook(text: "2", session_data: session_data)
    assert_match(/Thanks Ama, you chose pro/, last_sent_prompt)
  end

  def test_webhook_for_another_object_is_ignored
    context = run_raw_webhook({"object" => "page", "entry" => []})

    assert_equal :ok, context.controller.last_head_status
    assert_empty @sent
  end

  # Blocker 1 + Blocker 2, exercised together against the exact repro shape:
  # a carousel of 25 normal-length options, with media alongside it.
  def test_media_with_a_carousel_of_choices_stays_under_the_text_cap
    run_webhook(text: "start", session_data: {}, flow: MediaCarouselFlow)

    media_message, *body_messages, template_message = @sent.map { |s| s[:message] }

    assert_equal "image", media_message.dig(:attachment, :type)
    assert_equal "https://example.com/menu.png", media_message.dig(:attachment, :payload, :url)

    cap = FlowChat::Config.instagram.max_text_length
    refute_empty body_messages
    body_messages.each { |m| assert_operator m[:text].bytesize, :<=, cap }

    elements = template_message.dig(:attachment, :payload, :elements)
    assert_equal 25, elements.sum { |e| e[:buttons].length }
    assert_operator elements.length, :<=, FlowChat::Config.instagram.max_carousel_elements
  end

  # Blocker 3, on Instagram's (inherited) mapper: a typed "1" resolves
  # against the menu's position map, then the next screen is free text. A
  # stale map would rewrite a typed PIN digit into the menu's first choice.
  def test_typed_digit_on_free_text_screen_after_array_menu_stays_a_digit
    session_data = {}

    run_webhook(text: "start", session_data: session_data, flow: ArrayMenuThenPinFlow)
    assert_match(/1\. A very long label/, last_sent_prompt)

    run_webhook(text: "1", session_data: session_data, flow: ArrayMenuThenPinFlow)
    assert_match(/Enter your PIN/, last_sent_prompt)

    run_webhook(text: "1", session_data: session_data, flow: ArrayMenuThenPinFlow)
    assert_match(/PIN 1\./, last_sent_prompt)
  end

  private

  def processor_for(controller, session_data:)
    FlowChat::Processor.new(controller) do |config|
      config.use_gateway FlowChat::Instagram::Gateway::SendApi, @config
      config.use_session_store create_session_store(session_data)
    end
  end

  def run_webhook(text: nil, quick_reply: nil, session_data: {}, flow: RegistrationFlow)
    message = {"mid" => "mid.in.#{@sent.length}"}
    if quick_reply
      message["text"] = "tapped"
      message["quick_reply"] = {"payload" => quick_reply}
    else
      message["text"] = text
    end

    # entry.id and recipient.id both name the Instagram account, not the linked
    # page, which is the shape Meta sends under `object: "instagram"`.
    run_raw_webhook({
      "object" => "instagram",
      "entry" => [{
        "id" => "ig_1",
        "messaging" => [{
          "sender" => {"id" => "igsid_1"},
          "recipient" => {"id" => "ig_1"},
          "timestamp" => 1_700_000_000,
          "message" => message
        }]
      }]
    }, session_data: session_data, flow: flow)
  end

  def run_raw_webhook(body, session_data: {}, flow: RegistrationFlow)
    context = build_messaging_context(body)
    processor = processor_for(context.controller, session_data: session_data)
    processor.run(flow, :main_page)
    context
  end

  def last_sent_prompt
    @sent.last[:message][:text]
  end

  def last_sent_quick_reply_payload
    @sent.last[:message][:quick_replies].first[:payload]
  end

  # Mirrors messenger_integration_test.rb's helper: a session store that keeps
  # its data in a hash the test controls, so the same conversation carries
  # state across several webhooks even though a fresh instance is created by
  # Session::Middleware on every call.
  def create_session_store(data)
    Class.new do
      define_method(:initialize) { |_context| @data = data }
      define_method(:get) { |key| @data[key.to_s] }
      define_method(:set) { |key, value| @data[key.to_s] = value }
      define_method(:delete) { |key| @data.delete(key.to_s) }
      define_method(:clear) { @data.clear }
      define_method(:destroy) { @data.clear }
    end
  end
end
