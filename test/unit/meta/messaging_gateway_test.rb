require "test_helper"
require_relative "../../support/test_helpers"

class MessagingGatewayTest < Minitest::Test
  include FlowChat::TestSupport::TestHelpers

  # The base class is abstract. This exercises it directly rather than through
  # a platform, so a failure here is unambiguously the envelope's fault.
  class TestGateway < FlowChat::Meta::MessagingGateway
    def platform = :messenger

    def gateway_name = :messenger_send_api

    def configuration_class = FlowChat::Messenger::Configuration

    def client_class = FlowChat::Messenger::Client

    def renderer_class = FlowChat::Messenger::Renderer

    def self.choice_mapper_class = FlowChat::Messenger::Middleware::ChoiceMapper

    private

    def configuration_error_class
      FlowChat::Messenger::ConfigurationError
    end

    def platform_label
      "Messenger"
    end
  end

  def setup
    @config = FlowChat::Messenger::Configuration.new(nil)
    @config.page_id = "page_1"
    @config.access_token = "tok"
    @config.verify_token = "verify"
    @config.app_id = "our_app"
    @config.skip_signature_validation = true

    @app = proc { |context| [:text, "Response", nil, nil] }
    @gateway = TestGateway.new(@app, @config)
    @sent = []
    @gateway.client.define_singleton_method(:send_message) do |*args, **kwargs|
      {"message_id" => "mid.sent"}
    end
  end

  def test_text_message_populates_context
    context = post(messaging_payload({"message" => {"mid" => "mid.1", "text" => "Hello"}}))

    assert_equal "Hello", context.input
    assert_equal "psid_1", context["request.user_id"]
    assert_equal "psid_1", context["request.id"]
    assert_equal "mid.1", context["request.message_id"]
    assert_equal :messenger, context["request.platform"]
    assert_equal :messenger_send_api, context["request.gateway"]
    assert_nil context["request.msisdn"]
  end

  def test_quick_reply_payload_is_the_input
    context = post(messaging_payload({
      "message" => {"mid" => "mid.2", "text" => "Alpha", "quick_reply" => {"payload" => "choice_a"}}
    }))

    assert_equal "choice_a", context.input
  end

  def test_postback_payload_is_the_input
    context = post(messaging_payload({"postback" => {"mid" => "mid.3", "payload" => "get_started"}}))

    assert_equal "get_started", context.input
  end

  def test_echo_never_drives_a_flow_and_reports_its_origin
    events = capture_webhook_received do
      post(messaging_payload({
        "message" => {"mid" => "mid.4", "text" => "From a human", "is_echo" => true}
      }))
    end

    assert_equal 1, events.size
    assert_equal :human_agent, events.first[:echo_origin]
  end

  def test_echo_from_our_own_app_is_labelled_self
    events = capture_webhook_received do
      post(messaging_payload({
        "message" => {"mid" => "mid.5", "text" => "Ours", "is_echo" => true, "app_id" => "our_app"}
      }))
    end

    assert_equal :self, events.first[:echo_origin]
  end

  def test_delivery_receipt_publishes_status_and_leaves_the_flow_slot
    statuses = capture_events(FlowChat::Instrumentation::Events::MESSAGE_STATUS) do
      context = post({
        "object" => "page",
        "entry" => [{
          "id" => "page_1",
          "messaging" => [
            {"sender" => {"id" => "psid_1"}, "recipient" => {"id" => "page_1"}, "delivery" => {"mids" => ["mid.1"], "watermark" => 1}},
            {"sender" => {"id" => "psid_1"}, "recipient" => {"id" => "page_1"}, "message" => {"mid" => "mid.6", "text" => "Still here"}}
          ]
        }]
      })

      assert_equal "Still here", context.input, "a receipt must not spend the flow slot"
    end

    assert_equal 1, statuses.size
  end

  def test_second_message_in_one_delivery_does_not_run
    context = post({
      "object" => "page",
      "entry" => [{
        "id" => "page_1",
        "messaging" => [
          {"sender" => {"id" => "psid_1"}, "recipient" => {"id" => "page_1"}, "message" => {"mid" => "mid.7", "text" => "First"}},
          {"sender" => {"id" => "psid_2"}, "recipient" => {"id" => "page_1"}, "message" => {"mid" => "mid.8", "text" => "Second"}}
        ]
      }]
    })

    assert_equal "First", context.input
  end

  def test_event_for_another_account_is_rejected
    context = post({
      "object" => "page",
      "entry" => [{
        "id" => "someone_elses_page",
        "messaging" => [{"sender" => {"id" => "psid_1"}, "recipient" => {"id" => "someone_elses_page"}, "message" => {"mid" => "m", "text" => "Hi"}}]
      }]
    })

    assert_equal :forbidden, context.controller.last_head_status
  end

  def test_session_identifier_defaults_to_user_id
    middleware = FlowChat::Session::Middleware.allocate
    context = FlowChat::Context.new
    context["request.platform"] = :messenger

    assert_equal :user_id, middleware.send(:platform_default_identifier, context)
  end

  private

  def messaging_payload(event)
    {
      "object" => "page",
      "entry" => [{
        "id" => "page_1",
        "messaging" => [
          {"sender" => {"id" => "psid_1"}, "recipient" => {"id" => "page_1"}, "timestamp" => 1_700_000_000}.merge(event)
        ]
      }]
    }
  end

  def post(body)
    context = build_messaging_context(body)
    @gateway.call(context)
    context
  end
end
