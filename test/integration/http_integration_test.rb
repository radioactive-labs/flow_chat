require "test_helper"

class HttpIntegrationTest < Minitest::Test
  class GreetingFlow < FlowChat::Flow
    def main_page
      name = app.screen(:name) { |p| p.ask "What is your name?" }
      app.say "Hello, #{name}!"
    end
  end

  class ChoiceFlow < FlowChat::Flow
    def main_page
      choice = app.screen(:choice) do |p|
        p.select "Pick a color:", {"red" => "Red", "green" => "Green", "blue" => "Blue"}
      end
      app.say "You picked #{choice}!"
    end
  end

  class MediaFlow < FlowChat::Flow
    def main_page
      app.say "Here's an image", media: {type: :image, url: "https://example.com/photo.jpg"}
    end
  end

  class MultiStepFlow < FlowChat::Flow
    def main_page
      name = app.screen(:name) { |p| p.ask "What is your name?" }
      email = app.screen(:email) { |p| p.ask "What is your email?" }
      app.say "Thank you, #{name}! We'll contact you at #{email}."
    end
  end

  def setup
    # No external services to stub for HTTP Simple gateway
  end

  # ============================================================================
  # FULL FLOW INTEGRATION TESTS
  # ============================================================================

  def test_full_greeting_flow_prompts_for_name
    controller = create_http_controller(input: "")

    result = run_processor(controller, GreetingFlow)

    assert_equal :prompt, result[:type]
    assert_equal "What is your name?", result[:message]
    assert_equal "session_123", result[:session_id]
    assert_equal "user_456", result[:user_id]
    assert result[:timestamp].present?
  end

  def test_full_greeting_flow_completes_with_name
    # Set up session with name already collected
    session_data = {"name" => "Alice"}

    controller = create_http_controller(input: "ignored")

    result = run_processor(controller, GreetingFlow, session_data: session_data)

    assert_equal :terminal, result[:type]
    assert_equal "Hello, Alice!", result[:message]
  end

  def test_greeting_flow_collects_name_from_input
    # First request consumes input for $start$ flag (non-USSD behavior)
    # Second request with name in input should be stored
    session_data = {"$start$" => "initial"}

    controller = create_http_controller(input: "Bob")

    result = run_processor(controller, GreetingFlow, session_data: session_data)

    assert_equal :terminal, result[:type]
    assert_equal "Hello, Bob!", result[:message]
  end

  # ============================================================================
  # CHOICE FLOW TESTS
  # ============================================================================

  def test_choice_flow_shows_choices
    controller = create_http_controller(input: "")

    result = run_processor(controller, ChoiceFlow)

    assert_equal :prompt, result[:type]
    assert_equal "Pick a color:", result[:message]
    assert_equal [
      {key: "red", value: "Red"},
      {key: "green", value: "Green"},
      {key: "blue", value: "Blue"}
    ], result[:choices]
  end

  def test_choice_flow_completes_with_selection
    # Set up session with $start$ to indicate flow has been initialized
    session_data = {"$start$" => "start"}

    controller = create_http_controller(input: "green")

    result = run_processor(controller, ChoiceFlow, session_data: session_data)

    assert_equal :terminal, result[:type]
    assert_equal "You picked green!", result[:message]
  end

  def test_choice_flow_completes_with_numeric_selection
    # Test selecting by key
    session_data = {"$start$" => "start"}

    controller = create_http_controller(input: "blue")

    result = run_processor(controller, ChoiceFlow, session_data: session_data)

    assert_equal :terminal, result[:type]
    assert_equal "You picked blue!", result[:message]
  end

  # ============================================================================
  # MEDIA MESSAGE TESTS
  # ============================================================================

  def test_media_flow_returns_media_data
    controller = create_http_controller(input: "")

    result = run_processor(controller, MediaFlow)

    assert_equal :terminal, result[:type]
    assert_equal "Here's an image", result[:message]
    assert_equal({
      url: "https://example.com/photo.jpg",
      type: :image
    }, result[:media])
  end

  # ============================================================================
  # MULTI-STEP FLOW TESTS
  # ============================================================================

  def test_multi_step_flow_first_prompt
    controller = create_http_controller(input: "")

    result = run_processor(controller, MultiStepFlow)

    assert_equal :prompt, result[:type]
    assert_equal "What is your name?", result[:message]
  end

  def test_multi_step_flow_second_prompt
    session_data = {
      "$start$" => "start",
      "name" => "Alice"
    }

    controller = create_http_controller(input: "")

    result = run_processor(controller, MultiStepFlow, session_data: session_data)

    assert_equal :prompt, result[:type]
    assert_equal "What is your email?", result[:message]
  end

  def test_multi_step_flow_completion
    session_data = {
      "$start$" => "start",
      "name" => "Alice",
      "email" => "alice@example.com"
    }

    controller = create_http_controller(input: "ignored")

    result = run_processor(controller, MultiStepFlow, session_data: session_data)

    assert_equal :terminal, result[:type]
    assert_equal "Thank you, Alice! We'll contact you at alice@example.com.", result[:message]
  end

  def test_multi_step_flow_progressive_completion
    session_data = {}

    # Step 1: Initial request (input consumed for $start$)
    controller = create_http_controller(input: "Alice")
    result = run_processor(controller, MultiStepFlow, session_data: session_data)

    assert_equal :prompt, result[:type]
    assert_equal "What is your name?", result[:message]
    assert_equal "Alice", session_data["$start$"]

    # Step 2: Provide name
    controller = create_http_controller(input: "Alice")
    result = run_processor(controller, MultiStepFlow, session_data: session_data)

    assert_equal :prompt, result[:type]
    assert_equal "What is your email?", result[:message]
    assert_equal "Alice", session_data["name"]

    # Step 3: Provide email and complete
    controller = create_http_controller(input: "alice@example.com")
    result = run_processor(controller, MultiStepFlow, session_data: session_data)

    assert_equal :terminal, result[:type]
    assert_equal "Thank you, Alice! We'll contact you at alice@example.com.", result[:message]
  end

  # ============================================================================
  # CONTEXT EXTRACTION TESTS
  # ============================================================================

  def test_context_extracts_session_id
    controller = create_http_controller(
      input: "",
      session_id: "my_session_123"
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "my_session_123", captured_context["request.id"]
  end

  def test_context_extracts_user_id
    controller = create_http_controller(
      input: "",
      user_id: "user_789"
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "user_789", captured_context["request.user_id"]
  end

  def test_context_extracts_optional_user_params
    controller = create_http_controller(
      input: "",
      name: "John Doe",
      msisdn: "+1234567890",
      email: "john@example.com"
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "John Doe", captured_context["request.user_name"]
    assert_equal "+1234567890", captured_context["request.msisdn"]
    assert_equal "john@example.com", captured_context["request.email"]
  end

  def test_context_sets_platform_and_gateway
    controller = create_http_controller(input: "")

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal :http, captured_context["request.platform"]
    assert_equal :http_simple, captured_context["request.gateway"]
  end

  def test_context_extracts_input
    controller = create_http_controller(input: "test input")

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "test input", captured_context.input
  end

  def test_context_handles_empty_input
    controller = create_http_controller(input: "")

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "", captured_context.input
  end

  def test_context_handles_nil_input
    controller = create_http_controller(input: nil)

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "", captured_context.input
  end

  def test_context_extracts_http_metadata
    controller = create_http_controller(
      input: "",
      method: "POST",
      path: "/api/flow",
      user_agent: "TestAgent/1.0"
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert_equal "POST", captured_context["http.method"]
    assert_equal "/api/flow", captured_context["http.path"]
    assert_equal "TestAgent/1.0", captured_context["http.user_agent"]
  end

  def test_context_extracts_request_body
    controller = create_http_controller(
      input: "hello",
      extra_params: {"custom_field" => "custom_value"}
    )

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    body = captured_context["request.body"]
    assert_equal "hello", body["input"]
    assert_equal "custom_value", body["custom_field"]
  end

  def test_context_generates_message_id_and_timestamp
    controller = create_http_controller(input: "")

    captured_context = nil
    run_processor(controller, GreetingFlow) do |context|
      captured_context = context.dup
    end

    assert captured_context["request.message_id"].present?
    assert captured_context["request.timestamp"].present?
    # Message ID should be UUID format
    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i,
      captured_context["request.message_id"])
  end

  # ============================================================================
  # JSON REQUEST/RESPONSE FORMAT TESTS
  # ============================================================================

  def test_response_format_for_prompt
    controller = create_http_controller(input: "")

    result = run_processor(controller, GreetingFlow)

    # Verify all expected fields are present
    assert_equal :prompt, result[:type]
    assert result.key?(:session_id)
    assert result.key?(:user_id)
    assert result.key?(:timestamp)
    assert result.key?(:message)
    # Choices should not be present when there are none
    refute result.key?(:choices)
  end

  def test_response_format_for_terminal
    session_data = {"name" => "Test"}

    controller = create_http_controller(input: "ignored")

    result = run_processor(controller, GreetingFlow, session_data: session_data)

    assert_equal :terminal, result[:type]
    assert result.key?(:session_id)
    assert result.key?(:user_id)
    assert result.key?(:timestamp)
    assert result.key?(:message)
  end

  def test_response_format_with_choices
    controller = create_http_controller(input: "")

    result = run_processor(controller, ChoiceFlow)

    assert result.key?(:choices)
    assert_kind_of Array, result[:choices]
    result[:choices].each do |choice|
      assert choice.key?(:key)
      assert choice.key?(:value)
    end
  end

  def test_response_format_with_media
    controller = create_http_controller(input: "")

    result = run_processor(controller, MediaFlow)

    assert result.key?(:media)
    assert_equal "https://example.com/photo.jpg", result[:media][:url]
    assert_equal :image, result[:media][:type]
  end

  # ============================================================================
  # ERROR HANDLING TESTS
  # ============================================================================

  def test_gateway_requires_session_id
    error = assert_raises(FlowChat::Http::ConfigurationError) do
      FlowChat::Http::Gateway::Simple.new(nil, {user_id: "user_123"})
    end

    assert_match(/session_id/, error.message)
  end

  def test_gateway_requires_user_id
    error = assert_raises(FlowChat::Http::ConfigurationError) do
      FlowChat::Http::Gateway::Simple.new(nil, {session_id: "session_123"})
    end

    assert_match(/user_id/, error.message)
  end

  def test_gateway_rejects_invalid_http_methods
    controller = create_http_controller(input: "", method: "DELETE")

    # The gateway should call head :bad_request for invalid methods
    run_processor(controller, GreetingFlow)

    assert_equal :bad_request, controller.last_head_status
  end

  # ============================================================================
  # SESSION MANAGEMENT TESTS
  # ============================================================================

  def test_session_data_persists_across_screens
    session_data = {}

    # Step 1: Initial request
    controller = create_http_controller(input: "")
    run_processor(controller, MultiStepFlow, session_data: session_data)

    # Verify $start$ was set (non-USSD platform behavior)
    assert session_data.key?("$start$")

    # Step 2: Provide name
    controller = create_http_controller(input: "TestUser")
    run_processor(controller, MultiStepFlow, session_data: session_data)

    # Verify name was stored
    assert_equal "TestUser", session_data["name"]
  end

  def test_start_flag_behavior_for_non_ussd
    session_data = {}

    # First request: input should be consumed for $start$
    controller = create_http_controller(input: "first_input")
    result = run_processor(controller, GreetingFlow, session_data: session_data)

    # The flow should still prompt for name (first input consumed for $start$)
    assert_equal :prompt, result[:type]
    assert_equal "What is your name?", result[:message]
    assert_equal "first_input", session_data["$start$"]

    # Second request: input should be used normally
    controller = create_http_controller(input: "John")
    result = run_processor(controller, GreetingFlow, session_data: session_data)

    assert_equal :terminal, result[:type]
    assert_equal "Hello, John!", result[:message]
  end

  private

  def create_http_controller(input:, session_id: "session_123", user_id: "user_456",
    name: nil, msisdn: nil, email: nil,
    method: "POST", path: "/flow", user_agent: "TestClient/1.0",
    extra_params: {})
    params = {"input" => input}.merge(extra_params)

    controller = Object.new
    request = Object.new

    request.define_singleton_method(:get?) { method == "GET" }
    request.define_singleton_method(:post?) { method == "POST" }
    request.define_singleton_method(:method) { method }
    request.define_singleton_method(:path) { path }
    request.define_singleton_method(:user_agent) { user_agent }
    request.define_singleton_method(:params) { params }

    controller.define_singleton_method(:request) { request }
    controller.define_singleton_method(:head) { |status| @last_head_status = status }
    controller.define_singleton_method(:last_head_status) { @last_head_status }

    # Store rendered response for assertions
    controller.define_singleton_method(:render) { |options| @rendered = options }
    controller.define_singleton_method(:rendered) { @rendered }

    # Store user params for building the gateway
    controller.instance_variable_set(:@user_params, {
      session_id: session_id,
      user_id: user_id,
      name: name,
      msisdn: msisdn,
      email: email
    }.compact)

    controller.define_singleton_method(:user_params) { @user_params }

    controller
  end

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

  def run_processor(controller, flow_class, session_data: {}, &context_callback)
    session_store = create_session_store(session_data)
    user_params = controller.user_params

    processor = FlowChat::Processor.new(controller) do |c|
      c.use_gateway FlowChat::Http::Gateway::Simple, user_params
      c.use_session_store session_store

      if context_callback
        c.use_middleware Class.new {
          define_method(:initialize) { |app|
            @app = app
            @callback = context_callback
          }
          define_method(:call) { |context|
            @callback.call(context)
            @app.call(context)
          }
        }
      end
    end

    processor.run(flow_class, :main_page)

    # Return the rendered JSON response
    controller.rendered&.dig(:json)
  end
end
