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

    # Add head method to controller mock
    @controller.define_singleton_method(:head) do |status|
      @last_head_status = status
    end

    # Add method to retrieve last render for testing
    @controller.define_singleton_method(:last_render) { @last_render }

    # Add method to retrieve last head status for testing
    @controller.define_singleton_method(:last_head_status) { @last_head_status }

    @mock_app = lambda { |ctx| [:prompt, "Test response", {"1" => "Option 1"}, nil] }
    @user_params = {
      session_id: "test_session_123",
      user_id: "user_456"
    }
    @gateway = FlowChat::Http::Gateway::Simple.new(@mock_app, @user_params)
  end

  def test_initializes_with_app_and_user_params
    assert_equal @mock_app, @gateway.instance_variable_get(:@app)
    assert_equal @user_params, @gateway.instance_variable_get(:@user_params)
  end

  def test_requires_user_params
    error = assert_raises(FlowChat::Http::ConfigurationError) do
      FlowChat::Http::Gateway::Simple.new(@mock_app, {})
    end
    assert_match(/requires :session_id/, error.message)
  end

  def test_requires_session_id_and_user_id
    error = assert_raises(FlowChat::Http::ConfigurationError) do
      FlowChat::Http::Gateway::Simple.new(@mock_app, {session_id: "123"})
    end
    assert_match(/requires :user_id/, error.message)
  end

  def test_includes_instrumentation
    assert FlowChat::Http::Gateway::Simple.included_modules.include?(FlowChat::Instrumentation)
  end

  def test_call_sets_request_context
    @controller.request.params = {"input" => "Hello"}

    # Add the missing request methods to the mock
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:get?) { false }
    @controller.request.define_singleton_method(:post?) { true }
    @controller.request.define_singleton_method(:path) { "/http/webhook" }
    @controller.request.define_singleton_method(:user_agent) { "TestAgent/1.0" }

    @gateway.call(@context)

    assert_equal "test_session_123", @context["request.id"]
    assert_equal "user_456", @context["request.user_id"]
    assert_equal :http_simple, @context["request.gateway"]
    assert_equal :http, @context["request.platform"]
    assert_equal "POST", @context["http.method"]
    assert_equal "/http/webhook", @context["http.path"]
    assert_equal "TestAgent/1.0", @context["http.user_agent"]
    assert_equal "Hello", @context.input
  end

  def test_call_with_optional_msisdn_and_email
    gateway = FlowChat::Http::Gateway::Simple.new(@mock_app, {
      session_id: "sess_123",
      user_id: "user_789",
      msisdn: "+256700123456",
      email: "test@example.com"
    })

    @controller.request.params = {"input" => "Hello"}
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:get?) { false }
    @controller.request.define_singleton_method(:post?) { true }
    @controller.request.define_singleton_method(:path) { "/test" }
    @controller.request.define_singleton_method(:user_agent) { "Test/1.0" }

    gateway.call(@context)

    assert_equal "sess_123", @context["request.id"]
    assert_equal "user_789", @context["request.user_id"]
    assert_equal "+256700123456", @context["request.msisdn"]
    assert_equal "test@example.com", @context["request.email"]
  end

  def test_call_generates_message_id_and_timestamp
    @controller.request.params = {}
    @controller.request.define_singleton_method(:method) { "GET" }
    @controller.request.define_singleton_method(:get?) { true }
    @controller.request.define_singleton_method(:post?) { false }
    @controller.request.define_singleton_method(:path) { "/" }
    @controller.request.define_singleton_method(:user_agent) { "Browser/1.0" }

    @gateway.call(@context)

    refute_nil @context["request.message_id"]
    refute_nil @context["request.timestamp"]
    assert_match(/^[0-9a-f-]{36}$/, @context["request.message_id"])  # UUID format
  end

  def test_call_renders_json_response
    @controller.request.params = {"input" => "Test"}
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:get?) { false }
    @controller.request.define_singleton_method(:post?) { true }
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
      media = {url: "https://example.com/image.jpg", type: :image}
      [:prompt, "Check this image", nil, media]
    end
    gateway = FlowChat::Http::Gateway::Simple.new(mock_app_with_media, @user_params)

    @controller.request.params = {"input" => "Show image"}
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:get?) { false }
    @controller.request.define_singleton_method(:post?) { true }
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
    gateway = FlowChat::Http::Gateway::Simple.new(mock_terminal_app, @user_params)

    @controller.request.params = {"input" => "bye"}
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:get?) { false }
    @controller.request.define_singleton_method(:post?) { true }
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
    gateway = FlowChat::Http::Gateway::Simple.new(@mock_app, {
      session_id: "sess_123",
      user_id: "user_456",
      msisdn: "0700123456"  # Local format
    })

    @controller.request.params = {"input" => "Test"}
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:get?) { false }
    @controller.request.define_singleton_method(:post?) { true }
    @controller.request.define_singleton_method(:path) { "/test" }
    @controller.request.define_singleton_method(:user_agent) { "Test/1.0" }

    gateway.call(@context)

    # msisdn is now set directly from user_params (no normalization)
    assert_equal "0700123456", @context["request.msisdn"]
  end

  def test_instrumentation_events
    @controller.request.params = {"input" => "Test message"}
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:get?) { false }
    @controller.request.define_singleton_method(:post?) { true }
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

  def test_inbound_media_url_sets_request_media
    @controller.request.params = {"media_url" => "https://x/a.jpg", "media_type" => "image", "mime_type" => "image/jpeg"}
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:get?) { false }
    @controller.request.define_singleton_method(:post?) { true }
    @controller.request.define_singleton_method(:path) { "/http/webhook" }
    @controller.request.define_singleton_method(:user_agent) { "TestAgent/1.0" }

    @gateway.call(@context)

    assert_equal :image, @context["request.media"][:type]
    assert_equal "https://x/a.jpg", @context["request.media"][:url]
    assert_equal "image/jpeg", @context["request.media"][:mime_type]
    assert_equal FlowChat::Input::MEDIA, @context.input
  end

  def test_inbound_media_defaults_type_to_document
    @controller.request.params = {"media_url" => "https://x/a.pdf"}
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:get?) { false }
    @controller.request.define_singleton_method(:post?) { true }
    @controller.request.define_singleton_method(:path) { "/http/webhook" }
    @controller.request.define_singleton_method(:user_agent) { "TestAgent/1.0" }

    @gateway.call(@context)

    assert_equal :document, @context["request.media"][:type]
    assert_equal FlowChat::Input::MEDIA, @context.input
  end

  def test_text_input_takes_precedence_over_media
    @controller.request.params = {"input" => "hello", "media_url" => "https://x/a.jpg"}
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:get?) { false }
    @controller.request.define_singleton_method(:post?) { true }
    @controller.request.define_singleton_method(:path) { "/http/webhook" }
    @controller.request.define_singleton_method(:user_agent) { "TestAgent/1.0" }

    @gateway.call(@context)

    assert_equal "hello", @context.input
    assert_equal "https://x/a.jpg", @context["request.media"][:url]
  end

  def test_no_media_leaves_request_media_unset
    @controller.request.params = {"input" => "hi"}
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:get?) { false }
    @controller.request.define_singleton_method(:post?) { true }
    @controller.request.define_singleton_method(:path) { "/http/webhook" }
    @controller.request.define_singleton_method(:user_agent) { "TestAgent/1.0" }

    @gateway.call(@context)

    assert_nil @context["request.media"]
  end

  def test_sets_request_body_with_stringified_keys
    @controller.request.params = {
      "session_id" => "test_session_123",
      "msisdn" => "+256700123456",
      "user_id" => "user_456",
      "input" => "test input",
      "custom_field" => "custom value"
    }
    @controller.request.define_singleton_method(:method) { "POST" }
    @controller.request.define_singleton_method(:get?) { false }
    @controller.request.define_singleton_method(:post?) { true }
    @controller.request.define_singleton_method(:path) { "/test" }
    @controller.request.define_singleton_method(:user_agent) { "Test/1.0" }

    @gateway.call(@context)

    # Verify request.body is set
    assert_kind_of Hash, @context["request.body"]

    # Verify it contains the expected params
    assert_equal "test_session_123", @context["request.body"]["session_id"]
    assert_equal "+256700123456", @context["request.body"]["msisdn"]
    assert_equal "user_456", @context["request.body"]["user_id"]
    assert_equal "test input", @context["request.body"]["input"]
    assert_equal "custom value", @context["request.body"]["custom_field"]

    # Verify all keys are strings
    @context["request.body"].keys.each do |key|
      assert_kind_of String, key, "Expected all keys to be strings, but found #{key.class}"
    end
  end
end
