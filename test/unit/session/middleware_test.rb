require "test_helper"

class SessionMiddlewareTest < Minitest::Test
  def setup
    @context = FlowChat::Context.new
    @context["request.platform"] = :ussd
    @context["request.gateway"] = :nalo
    @context["request.msisdn"] = "+256700123456"
    @context["request.id"] = "request_123"
    @context["flow.name"] = "test_flow"
    
    # Create a mock session store class (not instance)
    @session_store_class = Class.new do
      def initialize(context)
        @data = {}
        @context = context
      end

      def get(key)
        @data[key.to_s]
      end

      def set(key, value)
        @data[key.to_s] = value
      end

      def delete(key)
        @data.delete(key.to_s)
      end

      def clear
        @data.clear
      end
      
      def destroy
        @data.clear
      end
      
      def exists?
        !@data.empty?
      end
    end
    
    @context["session.store"] = @session_store_class
    
    @mock_app = lambda do |context|
      [:prompt, "Test response", []]
    end
    
    @session_options = FlowChat::Config::SessionConfig.new
  end

  def test_initializes_with_app_and_session_options
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    
    assert_equal @session_options, middleware.instance_variable_get(:@session_options)
    assert_equal @mock_app, middleware.instance_variable_get(:@app)
  end

  def test_sets_session_id_and_creates_session
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    
    result = middleware.call(@context)
    
    # Should set session ID in context
    refute_nil @context["session.id"]
    
    # Should create session instance
    refute_nil @context.session
    
    # Should call next middleware and return result
    assert_equal [:prompt, "Test response", []], result
  end

  def test_uses_explicit_session_id_when_present
    explicit_id = "explicit_session_123"
    @context["session.id"] = explicit_id
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    assert_equal explicit_id, @context["session.id"]
  end

  def test_default_boundary_configuration
    # Default boundaries: [:flow, :provider, :platform]
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    parts = session_id.split(":")
    
    # Should contain: flow, platform, provider, identifier
    assert_includes session_id, "test_flow"      # flow
    assert_includes session_id, "ussd"           # platform  
    assert_includes session_id, "nalo"           # provider
    assert_includes session_id, "request_123"    # identifier (request_id for USSD)
  end

  def test_flow_boundary_isolation
    @session_options.boundaries = [:flow]
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    
    # Should only contain flow and identifier
    assert_includes session_id, "test_flow"
    assert_includes session_id, "request_123"
    
    # Should not contain platform or provider
    refute_includes session_id, "ussd"
    refute_includes session_id, "nalo"
  end

  def test_platform_boundary_isolation
    @session_options.boundaries = [:platform]
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    
    # Should contain platform and identifier
    assert_includes session_id, "ussd"
    assert_includes session_id, "request_123"
    
    # Should not contain flow or provider
    refute_includes session_id, "test_flow"
    refute_includes session_id, "nalo"
  end

  def test_provider_boundary_isolation
    @session_options.boundaries = [:provider]
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    
    # Should contain provider and identifier
    assert_includes session_id, "nalo"
    assert_includes session_id, "request_123"
    
    # Should not contain flow or platform
    refute_includes session_id, "test_flow"
    refute_includes session_id, "ussd"
  end

  def test_no_boundaries_global_sessions
    @session_options.boundaries = []
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    
    # Should only contain identifier (global session)
    assert_equal "request_123", session_id
  end

  def test_multiple_boundaries_combination
    @session_options.boundaries = [:flow, :platform]
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    
    # Should contain flow, platform, and identifier
    assert_includes session_id, "test_flow"
    assert_includes session_id, "ussd"
    assert_includes session_id, "request_123"
    
    # Should not contain provider
    refute_includes session_id, "nalo"
  end

  def test_ussd_platform_defaults_to_request_id_identifier
    @context["request.platform"] = :ussd
    @session_options.identifier = nil  # Platform chooses
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    assert_includes session_id, "request_123"
  end

  def test_whatsapp_platform_defaults_to_msisdn_identifier
    @context["request.platform"] = :whatsapp
    @session_options.identifier = nil  # Platform chooses
    @session_options.hash_phone_numbers = false  # Don't hash for easier testing
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    assert_includes session_id, "+256700123456"
  end

  def test_explicit_msisdn_identifier
    @session_options.identifier = :msisdn
    @session_options.hash_phone_numbers = false
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    assert_includes session_id, "+256700123456"
  end

  def test_explicit_request_id_identifier
    @session_options.identifier = :request_id
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    assert_includes session_id, "request_123"
  end

  def test_phone_number_hashing_enabled
    @session_options.identifier = :msisdn
    @session_options.hash_phone_numbers = true
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    
    # Should not contain raw phone number
    refute_includes session_id, "+256700123456"
    
    # Should contain hashed phone number (8 characters)
    parts = session_id.split(":")
    hashed_part = parts.last
    assert_equal 8, hashed_part.length
    assert_match /^[a-f0-9]{8}$/, hashed_part
  end

  def test_phone_number_hashing_disabled
    @session_options.identifier = :msisdn
    @session_options.hash_phone_numbers = false
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    assert_includes session_id, "+256700123456"
  end

  def test_invalid_identifier_type_raises_error
    @session_options.identifier = :invalid_type
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    
    error = assert_raises(RuntimeError) do
      middleware.call(@context)
    end
    
    assert_equal "Invalid session identifier type: invalid_type", error.message
  end

  def test_session_id_parts_joined_with_colons
    @session_options.boundaries = [:flow, :platform, :provider]
    @session_options.identifier = :request_id
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    expected = "test_flow:ussd:nalo:request_123"
    assert_equal expected, session_id
  end

  def test_empty_identifier_handled_gracefully
    @context["request.id"] = nil
    @context["request.msisdn"] = nil
    @session_options.identifier = :request_id
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    
    # Should not end with colon when identifier is empty
    refute_ends_with session_id, ":"
  end

  def test_unknown_platform_defaults_to_msisdn
    @context["request.platform"] = :unknown_platform
    @session_options.identifier = nil  # Platform chooses
    @session_options.hash_phone_numbers = false
    
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    session_id = @context["session.id"]
    assert_includes session_id, "+256700123456"
  end

  def test_context_gets_session_store_instance
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    middleware.call(@context)
    
    # Should create session instance using the store
    assert_respond_to @context.session, :get
    assert_respond_to @context.session, :set
  end

  def test_session_instrumentation_events
    original_notifications = ActiveSupport::Notifications.notifier
    test_events = []

    test_notifier = ActiveSupport::Notifications::Fanout.new
    test_notifier.subscribe(/.*flow_chat$/) do |name, start, finish, id, payload|
      test_events << {name: name, payload: payload}
    end

    begin
      ActiveSupport::Notifications.instance_variable_set(:@notifier, test_notifier)
      
      middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
      middleware.call(@context)
      
      # Should have session creation event
      session_events = test_events.select { |e| e[:name] == "session.created.flow_chat" }
      assert_equal 1, session_events.size
      
      event = session_events.first
      refute_nil event[:payload][:session_id]
              assert_equal "$Anonymous", event[:payload][:store_type]
      assert_equal :nalo, event[:payload][:gateway]
    ensure
      ActiveSupport::Notifications.instance_variable_set(:@notifier, original_notifications)
    end
  end

  def test_error_handling_and_logging
    error_app = lambda { |context| raise "Test error" }
    middleware = FlowChat::Session::Middleware.new(error_app, @session_options)
    
    assert_raises(RuntimeError) do
      middleware.call(@context)
    end
    
    # Error should be re-raised after logging
  end

  def test_session_id_generation_consistent
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    
    # Call twice with same context
    middleware.call(@context)
    first_session_id = @context["session.id"]
    
    # Reset context but keep same request data
    @context["session.id"] = nil
    @context.session = nil
    
    middleware.call(@context)
    second_session_id = @context["session.id"]
    
    # Should generate same session ID for same inputs
    assert_equal first_session_id, second_session_id
  end

  def test_hash_phone_number_method
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    
    hashed = middleware.send(:hash_phone_number, "+256700123456")
    
    # Should be 8 characters
    assert_equal 8, hashed.length
    
    # Should be hexadecimal
    assert_match /^[a-f0-9]+$/, hashed
    
    # Should be consistent
    hashed2 = middleware.send(:hash_phone_number, "+256700123456")
    assert_equal hashed, hashed2
    
    # Different numbers should produce different hashes
    hashed3 = middleware.send(:hash_phone_number, "+256700654321")
    refute_equal hashed, hashed3
  end

  def test_url_boundary_isolates_sessions_by_url
    @session_options.boundaries = [:url]
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    
    # Mock different request URLs
    request1 = OpenStruct.new(host: "tenant1.example.com", path: "/ussd")
    controller1 = OpenStruct.new(request: request1)
    @context["controller"] = controller1
    
    middleware.call(@context)
    session_id_1 = @context["session.id"]
    
    # Reset session.id for next call
    @context["session.id"] = nil
    @context.session = nil
    
    # Different host should get different session
    request2 = OpenStruct.new(host: "tenant2.example.com", path: "/ussd")
    controller2 = OpenStruct.new(request: request2)
    @context["controller"] = controller2
    
    middleware.call(@context)
    session_id_2 = @context["session.id"]
    
    refute_equal session_id_1, session_id_2
    assert_includes session_id_1, "tenant1.example.com_ussd"
    assert_includes session_id_2, "tenant2.example.com_ussd"
  end

  def test_url_boundary_with_path_isolation
    @session_options.boundaries = [:url]
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    
    # Different paths should get different sessions
    request1 = OpenStruct.new(host: "example.com", path: "/api/v1/ussd")
    controller1 = OpenStruct.new(request: request1)
    @context["controller"] = controller1
    
    middleware.call(@context)
    session_id_1 = @context["session.id"]
    
    # Reset session.id for next call
    @context["session.id"] = nil
    @context.session = nil
    
    request2 = OpenStruct.new(host: "example.com", path: "/api/v2/ussd")
    controller2 = OpenStruct.new(request: request2)
    @context["controller"] = controller2
    
    middleware.call(@context)
    session_id_2 = @context["session.id"]
    
    refute_equal session_id_1, session_id_2
    assert_includes session_id_1, "example.com_api_v1_ussd"
    assert_includes session_id_2, "example.com_api_v2_ussd"
  end

  def test_url_boundary_sanitizes_special_characters
    @session_options.boundaries = [:url]
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    
    request = OpenStruct.new(host: "test.example.com", path: "/api/v1/ussd?param=value")
    controller = OpenStruct.new(request: request)
    @context["controller"] = controller
    
    middleware.call(@context)
    session_id = @context["session.id"]
    
    # Should sanitize the URL to remove special characters
    assert_includes session_id, "test.example.com_api_v1_ussd_param_value"
  end

  def test_url_boundary_handles_long_urls
    @session_options.boundaries = [:url]
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    
    # Create a very long URL
    long_path = "/api/v1/ussd/with/very/long/path/that/exceeds/fifty/characters/in/length"
    request = OpenStruct.new(host: "verylongsubdomainnamethatmakestheentireurlverylongindeed.example.com", path: long_path)
    controller = OpenStruct.new(request: request)
    @context["controller"] = controller
    
    middleware.call(@context)
    session_id = @context["session.id"]
    
    # Should truncate and hash long URLs to keep session keys manageable
    parts = session_id.split(":")
    url_part = parts.first  # Get the URL part of the session ID (before the identifier)
    
    # Should be exactly 50 characters (41 first part + 1 underscore + 8 char hash)
    assert_equal 50, url_part.length
    
    # Should contain the beginning of the original URL (first 41 characters)
    assert url_part.start_with?("verylongsubdomainnamethatmakestheentireur")
    
    # Should end with underscore + 8 character hash
    assert_match /_[a-f0-9]{8}$/, url_part
  end

  def test_url_boundary_handles_root_path
    @session_options.boundaries = [:url]
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    
    request = OpenStruct.new(host: "example.com", path: "/")
    controller = OpenStruct.new(request: request)
    @context["controller"] = controller
    
    middleware.call(@context)
    session_id = @context["session.id"]
    
    # Root path should just use host
    assert_includes session_id, "example.com"
    refute_includes session_id, "example.com/"
  end

  def test_url_boundary_handles_missing_request
    @session_options.boundaries = [:url]
    middleware = FlowChat::Session::Middleware.new(@mock_app, @session_options)
    
    # No controller/request set
    @context["controller"] = nil
    
    middleware.call(@context)
    session_id = @context["session.id"]
    
    # Should handle gracefully without URL part
    refute_nil session_id
  end

  private

  def refute_ends_with(string, suffix)
    refute string.end_with?(suffix), "Expected '#{string}' not to end with '#{suffix}'"
  end
end 