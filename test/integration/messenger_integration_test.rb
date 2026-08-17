require "test_helper"
require_relative "../support/test_helpers"

class MessengerIntegrationTest < Minitest::Test
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

  # Media plus more than 3 choices used to be unreachable: Prompt raised
  # ArgumentError before this ever reached a renderer (Blocker 1). 4 choices
  # lands on Messenger's quick_replies rung (cap is 13), which is exactly the
  # combination the old guard made impossible to exercise end to end.
  class MediaChoiceFlow < FlowChat::Flow
    def main_page
      choice = app.screen(:plan) do |prompt|
        prompt.select "Choose a plan", {
          "basic" => "Basic Plan",
          "pro" => "Pro Plan",
          "team" => "Team Plan",
          "enterprise" => "Enterprise Plan"
        }, media: {type: :image, url: "https://example.com/plans.png"}
      end
      app.say "You picked #{choice}."
    end
  end

  # Array choices make key == label (see Prompt#normalize_choices), which is
  # what let a resolved choice collide with its own mapping key and defeat
  # clear_mappings_if_needed (Blocker 3). Long, similar-prefixed labels force
  # FlowChat::ChoiceTitles to number them, so a plain "1" resolves via the
  # position map exactly as in the reported repro.
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

  class TestAsyncJob < FlowChat::AsyncJob
    cattr_accessor :last_execution

    def execute(controller, **job_params)
      self.class.last_execution = {controller: controller, job_params: job_params}
    end
  end

  def setup
    @config = FlowChat::Messenger::Configuration.new(nil)
    @config.page_id = "page_1"
    @config.access_token = "tok"
    @config.verify_token = "verify"
    @config.skip_signature_validation = true

    # processor.gateway is not exposed by FlowChat::Processor (it only keeps
    # @gateway_class/@gateway_args privately, see lib/flow_chat/processor.rb),
    # so there is no built gateway/client instance to reach into after the
    # processor runs. Recording sends by patching Client#send_message at the
    # class level, and restoring the original method in teardown, is the
    # available seam.
    @sent = []
    sent = @sent
    @original_send_message = FlowChat::Messenger::Client.instance_method(:send_message)
    FlowChat::Messenger::Client.define_method(:send_message) do |to, prompt, choices: nil, media: nil|
      sent << {to: to, prompt: prompt, choices: choices, media: media}
      {"recipient_id" => to, "message_id" => "mid.#{sent.length}"}
    end
  end

  def teardown
    FlowChat::Messenger::Client.define_method(:send_message, @original_send_message)
  end

  def test_full_conversation
    session_data = {}

    run_webhook(text: "Hello", session_data: session_data)
    assert_match(/What is your name/, last_sent_prompt)

    run_webhook(text: "Ama", session_data: session_data)
    assert_match(/Choose a plan/, last_sent_prompt)

    tapped = last_sent_choices.keys.first
    run_webhook(quick_reply: tapped, session_data: session_data)
    assert_match(/Thanks Ama/, last_sent_prompt)
  end

  def test_async_mode_enqueues_instead_of_sending
    context = run_webhook(text: "Hello", async: true)

    assert_empty @sent
    assert_equal :ok, context.controller.last_head_status
  end

  # Blocker 1 + Blocker 2, exercised together: media rides alongside 4
  # choices (the guard used to make this raise before it ever reached a
  # renderer), and every posted part - the media and the choice message -
  # must land, with nothing over Messenger's text cap.
  def test_media_with_more_than_three_choices_sends_media_and_choices
    with_raw_posts do |posts|
      run_webhook(text: "start", flow: MediaChoiceFlow)

      media_post, choice_post = posts

      assert_equal "image", media_post.dig(:attachment, :type)
      assert_equal "https://example.com/plans.png", media_post.dig(:attachment, :payload, :url)

      assert_equal 4, choice_post[:quick_replies].length
      cap = FlowChat::Config.messenger.max_text_length
      posts.each do |post|
        assert_operator post[:text].to_s.bytesize, :<=, cap if post[:text]
      end
    end
  end

  # Blocker 3: a typed "1" resolves against the menu's position map (the
  # labels are long enough that FlowChat::ChoiceTitles numbers them), then
  # the very next screen is free text. A stale map would rewrite a typed PIN
  # digit into the menu's first choice; clear_mappings running unconditionally
  # before the app is called is what stops that.
  def test_typed_digit_on_free_text_screen_after_array_menu_stays_a_digit
    session_data = {}

    run_webhook(text: "start", session_data: session_data, flow: ArrayMenuThenPinFlow)
    assert_equal 2, last_sent_choices.length

    run_webhook(text: "1", session_data: session_data, flow: ArrayMenuThenPinFlow)
    assert_match(/Enter your PIN/, last_sent_prompt)

    run_webhook(text: "1", session_data: session_data, flow: ArrayMenuThenPinFlow)
    # The bug rewrote this reply into the first menu choice's full label
    # before the flow ever saw it. Bug present: "...and entered PIN A very
    # long label...". Fixed: the typed digit reaches the flow untouched.
    assert_match(/PIN 1\./, last_sent_prompt)
  end

  private

  def processor_for(controller, session_data:, async: false)
    FlowChat::Processor.new(controller) do |config|
      config.use_gateway FlowChat::Messenger::Gateway::SendApi, @config
      config.use_session_store create_session_store(session_data)
      config.use_async(TestAsyncJob) if async
    end
  end

  def run_webhook(text: nil, quick_reply: nil, session_data: {}, async: false, flow: RegistrationFlow)
    message = {"mid" => "mid.in.#{@sent.length}"}
    if quick_reply
      message["text"] = "tapped"
      message["quick_reply"] = {"payload" => quick_reply}
    else
      message["text"] = text
    end

    context = build_messaging_context({
      "object" => "page",
      "entry" => [{
        "id" => "page_1",
        "messaging" => [{
          "sender" => {"id" => "psid_1"},
          "recipient" => {"id" => "page_1"},
          "timestamp" => 1_700_000_000,
          "message" => message
        }]
      }]
    })

    # Only needed for the async path: GatewayAsyncSupport#enqueue_async_job
    # reads request.method directly (no rescue), and OpenStruct never defines
    # it because Object#method already exists and shadows method_missing.
    context.controller.request.define_singleton_method(:method) { "POST" } if async

    processor = processor_for(context.controller, session_data: session_data, async: async)

    if async
      TestAsyncJob.stub(:perform_later, ->(args) { true }) do
        processor.run(flow, :main_page)
      end
    else
      processor.run(flow, :main_page)
    end

    context
  end

  # setup patches Client#send_message so most tests can assert on the raw
  # prompt/choices/media the flow produced without caring how the client
  # turns that into wire posts. Asserting on what actually goes over the
  # wire - the point of the media/cap test above - needs the real render and
  # deliver path, so this restores send_message for the duration of the
  # block and patches Client#post_message instead, one level below deliver's
  # splitting logic, mirroring instagram_integration_test.rb's approach.
  def with_raw_posts
    FlowChat::Messenger::Client.define_method(:send_message, @original_send_message)
    posts = []
    original_post_message = FlowChat::Messenger::Client.instance_method(:post_message)
    FlowChat::Messenger::Client.define_method(:post_message) do |recipient_id, message, tag|
      posts << message
      {"recipient_id" => recipient_id, "message_id" => "mid.#{posts.length}"}
    end

    yield posts
  ensure
    FlowChat::Messenger::Client.define_method(:post_message, original_post_message)
  end

  def last_sent_prompt
    @sent.last[:prompt]
  end

  def last_sent_choices
    @sent.last[:choices]
  end

  # Mirrors whatsapp_integration_test.rb's helper: a session store that keeps
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
