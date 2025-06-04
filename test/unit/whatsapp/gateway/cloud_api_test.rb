require "test_helper"

class WhatsappCloudApiGatewayTest < Minitest::Test
  def setup
    # Create a mock configuration for testing
    @mock_config = FlowChat::Whatsapp::Configuration.new("test_config")
    @mock_config.verify_token = "test_verify_token"
    @mock_config.phone_number_id = "test_phone_id"
    @mock_config.access_token = "test_access_token"
    
    @gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", {}] }, @mock_config)
  end

  def test_get_request_webhook_verification
    context = create_context_with_request(
      method: :get,
      params: {
        "hub.mode" => "subscribe",
        "hub.verify_token" => "test_verify_token", 
        "hub.challenge" => "test_challenge"
      }
    )
    
    result = @gateway.call(context)
    
    # Should render the challenge as plain text
    assert_equal "test_challenge", context.controller.last_render[:plain]
  end

  def test_get_request_invalid_verify_token
    context = create_context_with_request(
      method: :get,
      params: {
        "hub.mode" => "subscribe",
        "hub.verify_token" => "invalid_token",
        "hub.challenge" => "test_challenge"
      }
    )
    
    result = @gateway.call(context)
    
    # Should return forbidden
    assert_equal :forbidden, context.controller.last_head_status
  end

  def test_post_request_text_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_text_message_payload("Hello", "wamid.test123")
    )
    
    @gateway.call(context)
    
    # Verify context was set correctly
    assert_equal "Hello", context.input
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "wamid.test123", context["request.message_id"]
    assert_equal "John Doe", context["request.contact_name"]
    assert_equal :whatsapp_cloud_api, context["request.gateway"]
    assert_equal "1702891800", context["request.timestamp"]
  end

  def test_post_request_button_response_processing
    context = create_context_with_request(
      method: :post,
      body: create_button_response_payload("btn_0", "Yes", "wamid.test456")
    )
    
    @gateway.call(context)
    
    assert_equal "btn_0", context.input
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "wamid.test456", context["request.message_id"]
  end

  def test_post_request_list_response_processing
    context = create_context_with_request(
      method: :post,
      body: create_list_response_payload("list_1", "Option 2", "wamid.test789")
    )
    
    @gateway.call(context)
    
    assert_equal "list_1", context.input
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "wamid.test789", context["request.message_id"]
  end

  def test_post_request_location_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_location_message_payload(0.3476, 32.5825, "wamid.location123")
    )
    
    @gateway.call(context)
    
    expected_location = {
      "latitude" => 0.3476,
      "longitude" => 32.5825,
      "name" => nil,
      "address" => nil
    }
    assert_equal expected_location, context["request.location"]
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "wamid.location123", context["request.message_id"]
    assert_equal "$location$", context.input
  end

  def test_post_request_media_message_processing
    context = create_context_with_request(
      method: :post,
      body: create_media_message_payload("media123", "image/jpeg", "wamid.media123")
    )
    
    @gateway.call(context)
    
    expected_media = {
      "type" => "image",
      "id" => "media123",
      "mime_type" => "image/jpeg",
      "caption" => nil
    }
    assert_equal expected_media, context["request.media"]
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "wamid.media123", context["request.message_id"]
    assert_equal "$media$", context.input
  end

  def test_empty_webhook_payload_handling
    context = create_context_with_request(
      method: :post,
      body: "{}"
    )
    
    @gateway.call(context)
    
    # Should handle gracefully and return ok
    assert_equal :ok, context.controller.last_head_status
  end

  def test_malformed_webhook_payload_handling
    context = create_context_with_request(
      method: :post,
      body: "invalid json"
    )
    
    # Should not crash - JSON.parse error is expected but should be handled
    assert_raises(JSON::ParserError) do
      @gateway.call(context)
    end
  end

  def test_unsupported_message_type_handling
    context = create_context_with_request(
      method: :post,
      body: create_unsupported_message_payload("wamid.unsupported123")
    )
    
    @gateway.call(context)
    
    # Should still set basic context but input might be nil
    assert_equal "+256700000000", context["request.msisdn"]
    assert_equal "wamid.unsupported123", context["request.message_id"]
    assert_nil context.input
  end

  def test_bad_request_handling
    context = create_context_with_request(method: :put)
    
    @gateway.call(context)
    
    assert_equal :bad_request, context.controller.last_head_status
  end

  # Tests for different message handling modes
  def test_inline_mode_message_handling
    # Mock inline mode
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :inline) do
      # Track app execution
      app_called = false
      test_app = proc do |context|
        app_called = true
        [:text, "Response", {}]
      end
      
      # Mock the client send_message call
      mock_client = Minitest::Mock.new
      mock_client.expect(:send_message, { "messages" => [{ "id" => "sent_123" }] }, ["+256700000000", [:text, "Response", {}]])
      
      # Stub the WhatsApp Client class to return our mock
      FlowChat::Whatsapp::Client.stub(:new, mock_client) do
        # Create gateway which will use our mocked client
        gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(test_app, @mock_config)
        context = create_context_with_request(
          method: :post,
          body: create_text_message_payload("Hello", "wamid.test123")
        )
        
        gateway.call(context)
        
        # Verify app was called and processed correctly
        assert app_called, "App should have been called"
        
        # In inline mode, message should be sent immediately
        mock_client.verify
        assert_equal({ "messages" => [{ "id" => "sent_123" }] }, context["whatsapp.message_result"])
      end
    end
  end

  def test_background_mode_message_handling
    # Mock background mode
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :background) do
      FlowChat::Config.whatsapp.stub(:background_job_class, 'TestBackgroundJob') do
        # Mock job class
        job_class = Minitest::Mock.new
        job_class.expect(:perform_later, true, [Hash])
        
        # Stub constantize to return our mock
        stub_constantize('TestBackgroundJob', job_class) do
          context = create_context_with_request(
            method: :post,
            body: create_text_message_payload("Hello", "wamid.test123")
          )
          
          @gateway.call(context)
          
          job_class.verify
        end
      end
    end
  end

  def test_background_mode_fallback_to_inline_when_job_missing
    # Mock background mode with missing job class
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :background) do
      FlowChat::Config.whatsapp.stub(:background_job_class, 'NonExistentJob') do
        # Create a simple mock client that tracks if send_message was called
        send_message_called = false
        mock_client = Object.new
        mock_client.define_singleton_method(:send_message) do |phone, response|
          send_message_called = true
          { "messages" => [{ "id" => "fallback_123" }] }
        end
        
        # Capture logged warning
        logged_warning = nil
        logger_mock = Minitest::Mock.new
        logger_mock.expect(:warn, nil) { |msg| logged_warning = msg; true }
        
        # Use the helper to make constantize fail for NonExistentJob
        stub_constantize_to_fail('NonExistentJob') do
          # Mock the WhatsApp Client class to return our mock
          FlowChat::Whatsapp::Client.stub(:new, mock_client) do
            Rails.stub(:logger, logger_mock) do
              gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", {}] }, @mock_config)
              context = create_context_with_request(
                method: :post,
                body: create_text_message_payload("Hello", "wamid.test123")
              )
              
              gateway.call(context)
              
              # Verify fallback behavior
              assert send_message_called, "Should have called send_message for fallback inline sending"
              assert_includes logged_warning, "Background mode requested but no NonExistentJob found. Falling back to inline sending."
              assert_equal({ "messages" => [{ "id" => "fallback_123" }] }, context["whatsapp.message_result"])
            end
          end
        end
        
        logger_mock.verify
      end
    end
  end

  def test_simulator_mode_message_handling
    # Mock simulator mode
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :simulator) do
      # Mock client build_message_payload method
      mock_client = Minitest::Mock.new
      mock_client.expect(:build_message_payload, { "to" => "+256700000000", "type" => "text", "text" => { "body" => "Response" } }, [[:text, "Response", {}], "+256700000000"])
      
      FlowChat::Whatsapp::Client.stub(:new, mock_client) do
        gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", {}] }, @mock_config)
        context = create_context_with_request(
          method: :post,
          body: create_text_message_payload("Hello", "wamid.test123")
        )
        
        gateway.call(context)
        
        mock_client.verify
        # Should render simulator response
        assert_equal "simulator", context.controller.last_render[:json][:mode]
        assert_equal true, context.controller.last_render[:json][:webhook_processed]
        assert_includes context.controller.last_render[:json], :would_send
        assert_includes context.controller.last_render[:json], :message_info
      end
    end
  end

  def test_simulator_mode_via_request_parameter
    # Even if global mode is inline, simulator parameter should override
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :inline) do
      mock_client = Minitest::Mock.new
      mock_client.expect(:build_message_payload, { "to" => "+256700000000", "type" => "text", "text" => { "body" => "Response" } }, [[:text, "Response", {}], "+256700000000"])
      
      FlowChat::Whatsapp::Client.stub(:new, mock_client) do
        gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(proc { |context| [:text, "Response", {}] }, @mock_config)
        context = create_context_with_request(
          method: :post,
          body: create_text_message_payload("Hello", "wamid.test123").merge("simulator_mode" => true)
        )
        
        gateway.call(context)
        
        mock_client.verify
        # Should render simulator response despite global inline mode
        assert_equal "simulator", context.controller.last_render[:json][:mode]
      end
    end
  end

  def test_flow_processing_happens_synchronously_in_background_mode
    # Verify that flow processing happens sync, even in background mode
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :background) do
      FlowChat::Config.whatsapp.stub(:background_job_class, 'TestBackgroundJob') do
        # Track if flow was called
        flow_called = false
        test_app = proc do |context|
          flow_called = true
          # Verify we have full context during flow execution
          assert_equal "Hello", context.input
          assert_equal "+256700000000", context["request.msisdn"]
          [:text, "Flow executed with context", {}]
        end
        
        job_class = Minitest::Mock.new
        job_class.expect(:perform_later, true, [Hash])
        
        stub_constantize('TestBackgroundJob', job_class) do
          gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(test_app, @mock_config)
          context = create_context_with_request(
            method: :post,
            body: create_text_message_payload("Hello", "wamid.test123")
          )
          
          gateway.call(context)
          
          # Flow should have been executed synchronously
          assert flow_called, "Flow should be executed synchronously even in background mode"
          job_class.verify
        end
      end
    end
  end

  def test_background_mode_preserves_controller_context
    # Verify that controller context is preserved during flow execution
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :background) do
      FlowChat::Config.whatsapp.stub(:background_job_class, 'TestBackgroundJob') do
        controller_preserved = false
        test_app = proc do |context|
          # Verify controller is available during flow execution
          controller_preserved = !context.controller.nil?
          [:text, "Controller context preserved", {}]
        end
        
        job_class = Minitest::Mock.new
        job_class.expect(:perform_later, true, [Hash])
        
        stub_constantize('TestBackgroundJob', job_class) do
          gateway = FlowChat::Whatsapp::Gateway::CloudApi.new(test_app, @mock_config)
          context = create_context_with_request(
            method: :post,
            body: create_text_message_payload("Hello", "wamid.test123")
          )
          
          gateway.call(context)
          
          assert controller_preserved, "Controller context should be preserved during flow execution"
          job_class.verify
        end
      end
    end
  end

  private

  def create_context_with_request(method:, params: {}, body: nil)
    context = FlowChat::Context.new
    
    # Create mock request
    request = OpenStruct.new(params: params)
    request.define_singleton_method(:get?) { method == :get }
    request.define_singleton_method(:post?) { method == :post }
    
    if body
      request.define_singleton_method(:body) do
        StringIO.new(body.is_a?(String) ? body : body.to_json)
      end
    end
    
    # Create mock controller
    controller = OpenStruct.new(request: request)
    
    # Track render calls
    controller.define_singleton_method(:render) do |options|
      @last_render = options
    end
    controller.define_singleton_method(:last_render) { @last_render }
    
    # Track head calls
    controller.define_singleton_method(:head) do |status, options = {}|
      @last_head_status = status
      @last_head_options = options
    end
    controller.define_singleton_method(:last_head_status) { @last_head_status }
    
    context["controller"] = controller
    context
  end

  def create_text_message_payload(text, message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "text" => { "body" => text },
              "type" => "text"
            }],
            "contacts" => [{
              "profile" => { "name" => "John Doe" },
              "wa_id" => "256700000000"
            }]
          }
        }]
      }]
    }
  end

  def create_button_response_payload(button_id, button_title, message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "interactive" => {
                "type" => "button_reply",
                "button_reply" => { "id" => button_id, "title" => button_title }
              },
              "type" => "interactive"
            }],
            "contacts" => [{
              "profile" => { "name" => "John Doe" },
              "wa_id" => "256700000000"
            }]
          }
        }]
      }]
    }
  end

  def create_list_response_payload(list_id, list_title, message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "interactive" => {
                "type" => "list_reply",
                "list_reply" => { "id" => list_id, "title" => list_title }
              },
              "type" => "interactive"
            }],
            "contacts" => [{
              "profile" => { "name" => "John Doe" },
              "wa_id" => "256700000000"
            }]
          }
        }]
      }]
    }
  end

  def create_location_message_payload(latitude, longitude, message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "location" => {
                "latitude" => latitude,
                "longitude" => longitude
              },
              "type" => "location"
            }],
            "contacts" => [{
              "profile" => { "name" => "John Doe" },
              "wa_id" => "256700000000"
            }]
          }
        }]
      }]
    }
  end

  def create_media_message_payload(media_id, mime_type, message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "image" => {
                "id" => media_id,
                "mime_type" => mime_type
              },
              "type" => "image"
            }],
            "contacts" => [{
              "profile" => { "name" => "John Doe" },
              "wa_id" => "256700000000"
            }]
          }
        }]
      }]
    }
  end

  def create_unsupported_message_payload(message_id)
    {
      "entry" => [{
        "changes" => [{
          "value" => {
            "messages" => [{
              "id" => message_id,
              "from" => "256700000000",
              "timestamp" => "1702891800",
              "type" => "unsupported"
            }],
            "contacts" => [{
              "profile" => { "name" => "John Doe" },
              "wa_id" => "256700000000"
            }]
          }
        }]
      }]
    }
  end
end 