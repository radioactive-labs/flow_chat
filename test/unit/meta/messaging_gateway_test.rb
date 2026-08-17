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

  # The simulator's whole point is completing a turn with no live
  # credentials at hand, so it cannot be expected to send an entry.id that
  # matches a real configuration.
  def test_simulator_mode_completes_a_turn_despite_a_mismatched_account_id
    with_simulator_secret do
      context = simulator_context("not_the_configured_account", cookie: FlowChat::Security.simulator_cookie)

      @gateway.call(context)

      assert_equal "Hi", context.input
      assert_equal "simulator", context.controller.last_render[:json][:mode]
    end
  end

  # The account check is skipped only once simulate? has already checked the
  # signed cookie - without one, the simulator_mode param alone changes
  # nothing, so a real mismatch is still rejected.
  def test_simulator_mode_param_without_a_valid_cookie_is_still_rejected
    with_simulator_secret do
      context = simulator_context("not_the_configured_account", cookie: nil)

      @gateway.call(context)

      assert_equal :forbidden, context.controller.last_head_status
    end
  end

  def test_session_identifier_defaults_to_user_id
    middleware = FlowChat::Session::Middleware.allocate
    context = FlowChat::Context.new
    context["request.platform"] = :messenger

    assert_equal :user_id, middleware.send(:platform_default_identifier, context)
  end

  # Meta delivers a shared location as an attachment like any image, but every
  # other gateway here puts one on request.location, and a flow reading
  # app.location should not have to know which platform it is on.
  def test_a_shared_location_lands_on_request_location
    context = post(messaging_payload({
      "message" => {
        "mid" => "mid.loc",
        "attachments" => [{
          "type" => "location",
          "title" => "Accra Mall",
          "payload" => {"coordinates" => {"lat" => 5.6205, "long" => -0.1731}}
        }]
      }
    }))

    assert_equal 5.6205, context["request.location"][:latitude]
    assert_equal(-0.1731, context["request.location"][:longitude])
    assert_equal "Accra Mall", context["request.location"][:name]
    assert_nil context["request.media"], "a location is not media"
  end

  # The other half of the same defect: the client wrapped its send in its own
  # MESSAGE_SENT instrument block while the gateway instrumented the same send,
  # so every successful delivery published the event twice.
  def test_message_sent_is_instrumented_exactly_once_on_a_successful_send
    sent, failed = capture_delivery_events do
      post(messaging_payload({"message" => {"mid" => "mid.1", "text" => "Hello"}}))
    end

    assert_equal 1, sent.length, "one delivery must publish message.sent exactly once"
    assert_equal 0, failed.length
  end

  # Regression: report_delivery_failure returns nil when send_message already
  # swallowed an API error, and handle_message_inline instrumented MESSAGE_SENT
  # regardless - so a delivery that never happened was counted as one that
  # did, alongside the MESSAGE_DELIVERY_FAILED event correctly fired for the
  # same send.
  def test_message_sent_is_not_instrumented_when_delivery_failed
    @gateway.client.define_singleton_method(:send_message) { |*args, **kwargs| nil }

    sent, failed = capture_delivery_events do
      post(messaging_payload({"message" => {"mid" => "mid.1", "text" => "Hello"}}))
    end

    assert_equal 1, failed.length, "the refused send must be reported once"
    assert_equal 0, sent.length, "message.sent must not fire for a delivery the platform refused"
  end

  def test_a_non_location_attachment_still_lands_on_request_media
    context = post(messaging_payload({
      "message" => {
        "mid" => "mid.img",
        "attachments" => [{"type" => "image", "payload" => {"url" => "https://cdn.example/a.png"}}]
      }
    }))

    assert_equal :image, context["request.media"][:type]
    assert_equal "https://cdn.example/a.png", context["request.media"][:url]
    assert_nil context["request.location"]
  end

  private

  def with_simulator_secret
    original = FlowChat::Config.simulator_secret
    FlowChat::Config.simulator_secret = "test_simulator_secret"
    yield
  ensure
    FlowChat::Config.simulator_secret = original
  end

  def simulator_context(account_id, cookie:)
    context = build_messaging_context({
      "object" => "page",
      "simulator_mode" => true,
      "entry" => [{
        "id" => account_id,
        "messaging" => [{"sender" => {"id" => "psid_1"}, "recipient" => {"id" => account_id}, "message" => {"mid" => "m", "text" => "Hi"}}]
      }]
    }, cookies: cookie ? {FlowChat::Security::SIMULATOR_COOKIE_NAME => cookie} : {})
    context["enable_simulator"] = true
    context
  end

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
