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

  def setup
    @config = FlowChat::Instagram::Configuration.new(nil)
    @config.page_id = "page_1"
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

  private

  def processor_for(controller, session_data:)
    FlowChat::Processor.new(controller) do |config|
      config.use_gateway FlowChat::Instagram::Gateway::SendApi, @config
      config.use_session_store create_session_store(session_data)
    end
  end

  def run_webhook(text: nil, quick_reply: nil, session_data: {})
    message = {"mid" => "mid.in.#{@sent.length}"}
    if quick_reply
      message["text"] = "tapped"
      message["quick_reply"] = {"payload" => quick_reply}
    else
      message["text"] = text
    end

    run_raw_webhook({
      "object" => "instagram",
      "entry" => [{
        "id" => "page_1",
        "messaging" => [{
          "sender" => {"id" => "igsid_1"},
          "recipient" => {"id" => "page_1"},
          "timestamp" => 1_700_000_000,
          "message" => message
        }]
      }]
    }, session_data: session_data)
  end

  def run_raw_webhook(body, session_data: {})
    context = build_messaging_context(body)
    processor = processor_for(context.controller, session_data: session_data)
    processor.run(RegistrationFlow, :main_page)
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
