require "test_helper"
require "time"
require "securerandom"

class UssdNaloGatewayTest < Minitest::Test
  def setup
    @app = mock_app
    @gateway = FlowChat::Ussd::Gateway::Nalo.new(@app)
    @context = FlowChat::Context.new
    @context["controller"] = mock_controller
  end

  def test_sets_context_from_nalo_params
    @context.controller.request.params = {
      "USERID" => "test_session_123",
      "MSISDN" => "256700123456",
      "USERDATA" => "1"
    }

    # Mock current time for consistent testing
    fixed_time = Time.parse("2023-12-01T10:30:00Z")
    Time.stub(:now, fixed_time) do
      @gateway.call(@context)
    end

    # Verify all context variables are set correctly
    assert_equal "test_session_123", @context["request.id"]
    assert_equal "+256700123456", @context["request.msisdn"]
    assert_equal "1", @context.input
    assert_equal :nalo, @context["request.gateway"]
    assert_nil @context["request.network"]

    # Verify new functionality
    assert_match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/, @context["request.message_id"])
    assert_equal "2023-12-01T10:30:00Z", @context["request.timestamp"]
  end

  def test_handles_empty_userdata
    @context.controller.request.params = {
      "USERID" => "test_session_456",
      "MSISDN" => "256700123456",
      "USERDATA" => ""
    }

    @gateway.call(@context)

    assert_nil @context.input
    assert_equal "test_session_456", @context["request.id"]
  end

  def test_handles_missing_userdata
    @context.controller.request.params = {
      "USERID" => "test_session_789",
      "MSISDN" => "256700123456"
    }

    @gateway.call(@context)

    assert_nil @context.input
    assert_equal "test_session_789", @context["request.id"]
  end

  def test_parses_msisdn_to_e164_format
    @context.controller.request.params = {
      "USERID" => "test_session_999",
      "MSISDN" => "256700123456",  # International format without +
      "USERDATA" => "test"
    }

    @gateway.call(@context)

    assert_equal "+256700123456", @context["request.msisdn"]
  end

  def test_renders_prompt_response
    @context.controller.request.params = {
      "USERID" => "test_session_prompt",
      "MSISDN" => "256700123456",
      "USERDATA" => "1"
    }

    # Mock app to return a prompt
    @app.call_result = [:prompt, "What is your name?", []]

    @gateway.call(@context)

    expected_response = {
      json: {
        USERID: "test_session_prompt",
        MSISDN: "256700123456",
        MSG: "What is your name?",
        MSGTYPE: true
      }
    }

    assert_equal expected_response, @context.controller.last_render
  end

  def test_renders_terminal_response
    @context.controller.request.params = {
      "USERID" => "test_session_terminal",
      "MSISDN" => "256700123456",
      "USERDATA" => "confirm"
    }

    # Mock app to return a terminal message
    @app.call_result = [:terminal, "Thank you for using our service!", []]

    @gateway.call(@context)

    expected_response = {
      json: {
        USERID: "test_session_terminal",
        MSISDN: "256700123456",
        MSG: "Thank you for using our service!",
        MSGTYPE: false
      }
    }

    assert_equal expected_response, @context.controller.last_render
  end

  def test_message_id_is_unique_across_calls
    @context.controller.request.params = {
      "USERID" => "test_session_unique",
      "MSISDN" => "256700123456",
      "USERDATA" => "1"
    }

    # First call
    @gateway.call(@context)
    first_message_id = @context["request.message_id"]

    # Second call with new context
    second_context = FlowChat::Context.new
    second_context["controller"] = mock_controller
    second_context.controller.request.params = {
      "USERID" => "test_session_unique2",
      "MSISDN" => "256700123456",
      "USERDATA" => "2"
    }

    @gateway.call(second_context)
    second_message_id = second_context["request.message_id"]

    # Message IDs should be different
    refute_equal first_message_id, second_message_id
    assert_match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/, first_message_id)
    assert_match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/, second_message_id)
  end

  def test_timestamp_advances_with_time
    @context.controller.request.params = {
      "USERID" => "test_session_time",
      "MSISDN" => "256700123456",
      "USERDATA" => "1"
    }

    # First call at a specific time
    first_time = Time.parse("2023-12-01T10:30:00Z")
    Time.stub(:now, first_time) do
      @gateway.call(@context)
    end
    first_timestamp = @context["request.timestamp"]

    # Second call 5 minutes later
    second_context = FlowChat::Context.new
    second_context["controller"] = mock_controller
    second_context.controller.request.params = {
      "USERID" => "test_session_time2",
      "MSISDN" => "256700123456",
      "USERDATA" => "2"
    }

    second_time = Time.parse("2023-12-01T10:35:00Z")
    Time.stub(:now, second_time) do
      @gateway.call(second_context)
    end
    second_timestamp = second_context["request.timestamp"]

    assert_equal "2023-12-01T10:30:00Z", first_timestamp
    assert_equal "2023-12-01T10:35:00Z", second_timestamp
    refute_equal first_timestamp, second_timestamp
  end

  def test_integrates_with_ussd_renderer
    @context.controller.request.params = {
      "USERID" => "test_renderer",
      "MSISDN" => "256700123456",
      "USERDATA" => "1"
    }

    # Mock app to return choices for rendering
    choices = ["1. Option A", "2. Option B", "3. Option C"]
    @app.call_result = [:prompt, "Choose an option:", choices]

    @gateway.call(@context)

    # The renderer should format the message with choices
    rendered_message = @context.controller.last_render[:json][:MSG]
    assert_includes rendered_message, "Choose an option:"
    # Note: Actual formatting depends on USSD renderer implementation
  end

  private

  def mock_app
    app = Object.new
    app.define_singleton_method(:call) do |context|
      @call_result || [:terminal, "Default response", []]
    end
    app.define_singleton_method(:call_result=) { |result| @call_result = result }
    app
  end

  def mock_controller
    controller = super

    # Add render tracking
    controller.define_singleton_method(:render) do |options|
      @last_render = options
    end

    controller.define_singleton_method(:last_render) { @last_render }

    controller
  end
end
