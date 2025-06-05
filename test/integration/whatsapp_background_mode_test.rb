require "test_helper"

class WhatsappBackgroundModeIntegrationTest < Minitest::Test
  # Test job that includes SendJobSupport for integration testing
  class TestWhatsappSendJob < BaseTestJob
    include FlowChat::Whatsapp::SendJobSupport

    def self.perform_later(send_data)
      super
    end

    def perform(send_data)
      perform_whatsapp_send(send_data)
    end
  end

  # Test flow for integration testing
  class TestWhatsappFlow < FlowChat::Flow
    def main_page
      name = app.screen(:name) do |prompt|
        if app.input && !app.input.empty?
          prompt.ask "Hello #{app.input}! What can I help you with?",
            transform: ->(input) { input.strip.downcase }
        else
          prompt.ask "Welcome! What's your name?",
            transform: ->(input) { input.strip.titleize }
        end
      end

      app.say "Thanks #{name}! Your request has been processed."
    end
  end

  def setup
    @mock_config = FlowChat::Whatsapp::Configuration.new("test_config")
    @mock_config.verify_token = "test_verify_token"
    @mock_config.phone_number_id = "test_phone_id"
    @mock_config.access_token = "test_access_token"
    @mock_config.app_secret = "test_app_secret"

    # Clear any previous jobs
    BaseTestJob.clear_performed_jobs

    # Ensure cache is set up for CacheSessionStore tests
    unless FlowChat::Config.cache
      FlowChat::Config.cache = begin
        cache = Object.new
        data = {}

        cache.define_singleton_method(:read) { |key| data[key] }
        cache.define_singleton_method(:write) { |key, value, options = {}| data[key] = value }
        cache.define_singleton_method(:delete) { |key| data.delete(key) }
        cache.define_singleton_method(:exist?) { |key| data.key?(key) }
        cache.define_singleton_method(:clear) { data.clear }

        cache
      end
    end
  end

  def test_complete_background_mode_flow
    # Configure background mode
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :background) do
      FlowChat::Config.whatsapp.stub(:background_job_class, "WhatsappBackgroundModeIntegrationTest::TestWhatsappSendJob") do
        # Track what arguments are passed to send_message
        actual_calls = []

        # Mock the WhatsApp client for final sending
        mock_client = Object.new
        mock_client.define_singleton_method(:send_message) do |phone, response|
          actual_calls << [phone, response]
          {"messages" => [{"id" => "sent_123"}]}
        end

        FlowChat::Whatsapp::Client.stub(:new, mock_client) do
          # Create context simulating WhatsApp webhook
          context = create_context_with_request(
            method: :post,
            body: create_text_message_payload("John", "wamid.test123")
          )

          # Create processor with the mock controller
          processor = FlowChat::Whatsapp::Processor.new(context["controller"]) do |config|
            config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, @mock_config
            config.use_session_store FlowChat::Session::CacheSessionStore
          end

          # Process the webhook by running the flow
          processor.run(TestWhatsappFlow, :main_page)

          puts "Jobs performed: #{TestWhatsappSendJob.performed_jobs.length}"
          puts "Jobs: #{TestWhatsappSendJob.performed_jobs.inspect}"

          # Check what was actually called
          puts "Actual calls: #{actual_calls.inspect}"
          puts "Number of calls: #{actual_calls.length}"
          if actual_calls.length > 0
            puts "First call: #{actual_calls[0].inspect}"
            if actual_calls.length > 1
              puts "Second call: #{actual_calls[1].inspect}"
            end
          end
        end
      end
    end
  end

  def test_multi_step_flow_with_session_persistence
    # Test that sessions work correctly in background mode
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :background) do
      FlowChat::Config.whatsapp.stub(:background_job_class, "WhatsappBackgroundModeIntegrationTest::TestWhatsappSendJob") do
        # Mock session store
        session_data = {}
        mock_session_store = Class.new do
          define_method(:initialize) { |context| @context = context }
          define_method(:get) { |key| session_data[@context["request.msisdn"]] ? session_data[@context["request.msisdn"]][key.to_s] : nil }
          define_method(:set) { |key, value|
            session_data[@context["request.msisdn"]] ||= {}
            session_data[@context["request.msisdn"]][key.to_s] = value
          }
          define_method(:delete) { |key|
            return unless session_data[@context["request.msisdn"]]
            session_data[@context["request.msisdn"]].delete(key.to_s)
          }
          define_method(:clear) { session_data.delete(@context["request.msisdn"]) }
          define_method(:destroy) { session_data.delete(@context["request.msisdn"]) }
        end

        mock_client = Minitest::Mock.new
        # First request - ask for name
        mock_client.expect(:send_message, {"messages" => [{"id" => "msg1"}]}, ["+256700000000", [:text, "Welcome! What's your name?", {}]])
        # Second request - respond with name
        mock_client.expect(:send_message, {"messages" => [{"id" => "msg2"}]}, ["+256700000000", [:text, "Thanks John! Your request has been processed.", {}]])

        FlowChat::Whatsapp::Client.stub(:new, mock_client) do
          # First request - no input (start of conversation)
          context1 = create_context_with_request(
            method: :post,
            body: create_text_message_payload("", "wamid.test1")
          )

          processor1 = FlowChat::Whatsapp::Processor.new(context1["controller"]) do |config|
            config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, @mock_config
            config.use_session_store mock_session_store
          end

          processor1.run(TestWhatsappFlow, :main_page)

          # Second request - provide name
          context2 = create_context_with_request(
            method: :post,
            body: create_text_message_payload("John", "wamid.test2")
          )

          processor2 = FlowChat::Whatsapp::Processor.new(context2["controller"]) do |config|
            config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, @mock_config
            config.use_session_store mock_session_store
          end

          processor2.run(TestWhatsappFlow, :main_page)

          # Verify both interactions were processed and jobs enqueued
          assert_equal 2, TestWhatsappSendJob.performed_jobs.length

          # Verify session persistence allowed flow to continue
          first_response = TestWhatsappSendJob.performed_jobs[0][:args][0][:response]
          second_response = TestWhatsappSendJob.performed_jobs[1][:args][0][:response]

          assert_equal [:text, "Welcome! What's your name?", {}], first_response
          assert_equal [:text, "Thanks John! Your request has been processed.", {}], second_response

          mock_client.verify
        end
      end
    end
  end

  def test_error_handling_in_background_mode
    # Test that errors during flow processing are handled gracefully
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :background) do
      FlowChat::Config.whatsapp.stub(:background_job_class, "WhatsappBackgroundModeIntegrationTest::TestWhatsappSendJob") do
        # Create a flow that raises an error
        error_flow = Class.new(FlowChat::Flow) do
          def main_page
            raise StandardError, "Flow processing error"
          end
        end

        context = create_context_with_request(
          method: :post,
          body: create_text_message_payload("Hello", "wamid.error_test")
        )

        processor = FlowChat::Whatsapp::Processor.new(context["controller"]) do |config|
          config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, @mock_config
          config.use_session_store FlowChat::Session::CacheSessionStore
        end

        # Error should be raised during synchronous flow processing
        assert_raises(StandardError) do
          processor.run(error_flow, :main_page)
        end

        # No job should be enqueued since flow failed
        assert_equal 0, TestWhatsappSendJob.performed_jobs.length
      end
    end
  end

  def test_mode_override_via_request_parameter
    # Test that simulator_mode parameter overrides global background mode
    FlowChat::Config.whatsapp.stub(:message_handling_mode, :background) do
      FlowChat::Config.whatsapp.stub(:background_job_class, "WhatsappBackgroundModeIntegrationTest::TestWhatsappSendJob") do
        # Set up global simulator secret for cookie validation
        FlowChat::Config.simulator_secret = "test_simulator_secret_123"
        
        # Generate valid simulator cookie
        timestamp = Time.now.to_i
        message = "simulator:#{timestamp}"
        signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), "test_simulator_secret_123", message)
        valid_cookie = "#{timestamp}:#{signature}"

        # Include simulator_mode in request body
        context = create_context_with_request(
          method: :post,
          body: create_text_message_payload("", "wamid.sim_test").merge("simulator_mode" => true),
          cookies: {
            "flowchat_simulator" => valid_cookie
          }
        )

        # Enable simulator mode for this processor
        processor = FlowChat::Whatsapp::Processor.new(context["controller"], enable_simulator: true) do |config|
          config.use_gateway FlowChat::Whatsapp::Gateway::CloudApi, @mock_config
          config.use_session_store FlowChat::Session::CacheSessionStore
        end

        processor.run(TestWhatsappFlow, :main_page)

        # Should use simulator mode, not background mode
        assert_equal 0, TestWhatsappSendJob.performed_jobs.length

        # Should render simulator response
        controller = context["controller"]
        refute_nil controller.last_render
        assert_equal "simulator", controller.last_render[:json][:mode]
        assert_equal true, controller.last_render[:json][:webhook_processed]
        refute_nil controller.last_render[:json][:would_send]
      end
    end
  ensure
    # Clean up
    FlowChat::Config.simulator_secret = nil
  end

  private

  def create_context_with_request(method:, params: {}, body: nil, cookies: {})
    context = FlowChat::Context.new

    # Calculate webhook signature if body is provided and app_secret is configured
    headers = {}
    if body && @mock_config.app_secret
      body_string = body.is_a?(String) ? body : body.to_json
      signature = OpenSSL::HMAC.hexdigest(
        OpenSSL::Digest.new("sha256"),
        @mock_config.app_secret,
        body_string
      )
      headers["X-Hub-Signature-256"] = "sha256=#{signature}"
    end

    # Create mock request
    request = OpenStruct.new(params: params, headers: headers, cookies: cookies)
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
              "text" => {"body" => text},
              "type" => "text"
            }],
            "contacts" => [{
              "profile" => {"name" => "John Doe"},
              "wa_id" => "256700000000"
            }]
          }
        }]
      }]
    }
  end
end
