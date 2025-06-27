require "test_helper"

class HttpSimpleGatewayTest < Minitest::Test
  def setup
    @context = FlowChat::Context.new
    @controller = mock_controller
    @context["controller"] = @controller
    
    # Add render method to controller mock
    @controller.define_singleton_method(:render) do |options|
      @last_render = options
    end
    
    # Add method to retrieve last render for testing
    @controller.define_singleton_method(:last_render) { @last_render }
    
    @mock_app = lambda { |ctx| [:prompt, "Test response", { "1" => "Option 1" }, nil] }
    @gateway = FlowChat::Http::Gateway::Simple.new(@mock_app)
  end

  def test_initializes_with_app
    assert_equal @mock_app, @gateway.instance_variable_get(:@app)
  end

  def test_includes_instrumentation
    assert FlowChat::Http::Gateway::Simple.included_modules.include?(FlowChat::Instrumentation)
  end

  def test_call_sets_request_context
    @controller.request.params = {
      "session_id" => "test_session_123",
      "msisdn" => "+256700123456",
      "input" => "Hello"
    }
    
    # Add the missing request methods to the mock
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:path) { "/http/webhook" }
    @controller.request.define_singleton_method(:user_agent) { "TestAgent/1.0" }

    @gateway.call(@context)

    assert_equal "test_session_123", @context["request.id"]
    assert_equal "+256700123456", @context["request.msisdn"]
    assert_equal "+256700123456", @context["request.user_id"]
    assert_equal :http_simple, @context["request.gateway"]
    assert_equal :http, @context["request.platform"]
    assert_equal "POST", @context["request.method"]
    assert_equal "/http/webhook", @context["request.path"]
    assert_equal "TestAgent/1.0", @context["request.user_agent"]
    assert_equal "Hello", @context.input
  end

  def test_call_generates_defaults_when_missing
    @controller.request.params = {}
    @controller.request.define_singleton_method(:method) { "GET" }
    @controller.request.define_singleton_method(:path) { "/" }
    @controller.request.define_singleton_method(:user_agent) { "Browser/1.0" }

    @gateway.call(@context)

    refute_nil @context["request.id"]
    refute_nil @context["request.message_id"]
    refute_nil @context["request.timestamp"]
    assert_equal @context["request.id"], @context["request.user_id"]  # Falls back to request.id
  end

  def test_call_handles_user_id_param
    @controller.request.params = {
      "user_id" => "custom_user_123",
      "input" => "Test message"
    }
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:path) { "/test" }
    @controller.request.define_singleton_method(:user_agent) { "Test/1.0" }

    @gateway.call(@context)

    assert_equal "custom_user_123", @context["request.user_id"]
    assert_equal "Test message", @context.input
  end

  def test_call_renders_json_response
    @controller.request.params = { "input" => "Test" }
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:path) { "/test" }
    @controller.request.define_singleton_method(:user_agent) { "Test/1.0" }

    # Mock the render method to capture the response
    rendered_response = nil
    @controller.define_singleton_method(:render) do |options|
      rendered_response = options[:json]
    end

    @gateway.call(@context)

    refute_nil rendered_response
    assert_equal :prompt, rendered_response[:type]
    assert_equal "Test response", rendered_response[:message]
    assert_equal 1, rendered_response[:choices].size
    assert_equal "1", rendered_response[:choices][0][:key]
    assert_equal "Option 1", rendered_response[:choices][0][:value]
    refute_nil rendered_response[:session_id]
    refute_nil rendered_response[:user_id]
    refute_nil rendered_response[:timestamp]
  end

  def test_call_with_media_response
    mock_app_with_media = lambda do |ctx|
      media = { url: "https://example.com/image.jpg", type: :image }
      [:prompt, "Check this image", nil, media]
    end
    gateway = FlowChat::Http::Gateway::Simple.new(mock_app_with_media)

    @controller.request.params = { "input" => "Show image" }
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:path) { "/test" }
    @controller.request.define_singleton_method(:user_agent) { "Test/1.0" }

    rendered_response = nil
    @controller.define_singleton_method(:render) do |options|
      rendered_response = options[:json]
    end

    gateway.call(@context)

    assert_equal "Check this image", rendered_response[:message]
    assert_equal "https://example.com/image.jpg", rendered_response[:media][:url]
    assert_equal :image, rendered_response[:media][:type]
  end

  def test_call_with_terminal_response
    mock_terminal_app = lambda { |ctx| [:terminal, "Goodbye!", nil, nil] }
    gateway = FlowChat::Http::Gateway::Simple.new(mock_terminal_app)

    @controller.request.params = { "input" => "bye" }
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:path) { "/test" }
    @controller.request.define_singleton_method(:user_agent) { "Test/1.0" }

    rendered_response = nil
    @controller.define_singleton_method(:render) do |options|
      rendered_response = options[:json]
    end

    gateway.call(@context)

    assert_equal :terminal, rendered_response[:type]
    assert_equal "Goodbye!", rendered_response[:message]
  end

  def test_phone_number_normalization
    @controller.request.params = {
      "msisdn" => "0700123456",  # Local format
      "input" => "Test"
    }
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:path) { "/test" }
    @controller.request.define_singleton_method(:user_agent) { "Test/1.0" }

    # Mock PhoneNumberUtil to test normalization
    original_method = FlowChat::PhoneNumberUtil.method(:to_e164)
    FlowChat::PhoneNumberUtil.define_singleton_method(:to_e164) do |phone|
      phone == "0700123456" ? "+256700123456" : original_method.call(phone)
    end

    begin
      @gateway.call(@context)

      assert_equal "+256700123456", @context["request.msisdn"]
      assert_equal "+256700123456", @context["request.user_id"]
    ensure
      # Restore original method
      FlowChat::PhoneNumberUtil.define_singleton_method(:to_e164, original_method)
    end
  end

  def test_instrumentation_events
    @controller.request.params = { "input" => "Test message" }
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:path) { "/test" }
    @controller.request.define_singleton_method(:user_agent) { "Test/1.0" }
    @controller.define_singleton_method(:render) { |options| }

    # Track instrumentation calls
    message_received_called = false
    message_sent_called = false

    received_payload = nil
    sent_payload = nil
    
    original_instrument = @gateway.method(:instrument)
    @gateway.define_singleton_method(:instrument) do |event, payload|
      case event
      when FlowChat::Instrumentation::Events::MESSAGE_RECEIVED
        message_received_called = true
        received_payload = payload
      when FlowChat::Instrumentation::Events::MESSAGE_SENT
        message_sent_called = true
        sent_payload = payload
      end
    end

    begin
      @gateway.call(@context)

      assert message_received_called, "MESSAGE_RECEIVED event should be instrumented"
      assert message_sent_called, "MESSAGE_SENT event should be instrumented"
      
      # Test the payload contents
      assert_equal "Test message", received_payload[:message]
      assert_equal :http_simple, sent_payload[:gateway]
      assert_equal :http, sent_payload[:platform]
    ensure
      # Restore original method
      @gateway.define_singleton_method(:instrument, original_instrument)
    end
  end
end 