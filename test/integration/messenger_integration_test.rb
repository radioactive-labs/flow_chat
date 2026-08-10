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

  private

  def processor_for(controller, session_data:, async: false)
    FlowChat::Processor.new(controller) do |config|
      config.use_gateway FlowChat::Messenger::Gateway::SendApi, @config
      config.use_session_store create_session_store(session_data)
      config.use_async(TestAsyncJob) if async
    end
  end

  def run_webhook(text: nil, quick_reply: nil, session_data: {}, async: false)
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
        processor.run(RegistrationFlow, :main_page)
      end
    else
      processor.run(RegistrationFlow, :main_page)
    end

    context
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
