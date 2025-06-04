require "test_helper"

class SendJobSupportTest < Minitest::Test
  def setup
    @config = FlowChat::Whatsapp::Configuration.new("test_config")
    @config.access_token = "test_access_token"
    @config.phone_number_id = "test_phone_number_id"
    @config.verify_token = "test_verify_token"

    @send_data = {
      msisdn: "+1234567890",
      response: [:text, "Hello, World!", {}],
      config_name: "test_config"
    }

    # Register the test config
    FlowChat::Whatsapp::Configuration.register("test_config", @config)

    # Clear previous jobs
    BaseTestJob.clear_performed_jobs

    # Create job instance
    @job = TestWhatsappJob.new

    # Mock client
    @mock_client = Minitest::Mock.new
  end

  def test_perform_whatsapp_send_success
    # Mock successful API response
    api_result = {"messages" => [{"id" => "msg_123"}]}

    FlowChat::Whatsapp::Configuration.stub(:exists?, true) do
      FlowChat::Whatsapp::Configuration.stub(:get, @config) do
        FlowChat::Whatsapp::Client.stub(:new, @mock_client) do
          @mock_client.expect(:send_message, api_result, ["+1234567890", [:text, "Hello, World!", {}]])

          @job.perform(@send_data)

          assert_equal 1, @job.success_callbacks.length, "Success callback should be called"
          assert_equal 0, @job.error_callbacks.length, "Error callback should not be called"
          @mock_client.verify
        end
      end
    end
  end

  def test_perform_whatsapp_send_api_failure
    FlowChat::Whatsapp::Configuration.stub(:exists?, true) do
      FlowChat::Whatsapp::Configuration.stub(:get, @config) do
        FlowChat::Whatsapp::Client.stub(:new, @mock_client) do
          @mock_client.expect(:send_message, nil, ["+1234567890", [:text, "Hello, World!", {}]])
          @mock_client.expect(:send_text, true, ["+1234567890", "⚠️ We're experiencing technical difficulties. Please try again in a few minutes."])

          error = assert_raises(RuntimeError) do
            @job.perform(@send_data)
          end

          assert_equal "WhatsApp API call failed", error.message
          assert_equal 0, @job.success_callbacks.length, "Success callback should not be called"
          assert_equal 1, @job.error_callbacks.length, "Error callback should be called"
          @mock_client.verify
        end
      end
    end
  end

  def test_perform_whatsapp_send_network_error
    network_error = StandardError.new("Network timeout")

    FlowChat::Whatsapp::Configuration.stub(:exists?, true) do
      FlowChat::Whatsapp::Configuration.stub(:get, @config) do
        FlowChat::Whatsapp::Client.stub(:new, @mock_client) do
          @mock_client.expect(:send_message, proc { raise network_error }, ["+1234567890", [:text, "Hello, World!", {}]])
          @mock_client.expect(:send_text, true, ["+1234567890", "⚠️ We're experiencing technical difficulties. Please try again in a few minutes."])

          error = assert_raises(StandardError) do
            @job.perform(@send_data)
          end

          assert_equal "Network timeout", error.message
          assert_equal 0, @job.success_callbacks.length, "Success callback should not be called"
          assert_equal 1, @job.error_callbacks.length, "Error callback should be called"
          @mock_client.verify
        end
      end
    end
  end

  def test_resolve_whatsapp_config_with_named_config
    FlowChat::Whatsapp::Configuration.stub(:exists?, true) do
      FlowChat::Whatsapp::Configuration.stub(:get, @config) do
        config = @job.send(:resolve_whatsapp_config, @send_data)
        assert_equal @config, config
      end
    end
  end

  def test_resolve_whatsapp_config_fallback_to_credentials
    FlowChat::Whatsapp::Configuration.stub(:exists?, false) do
      FlowChat::Whatsapp::Configuration.stub(:from_credentials, @config) do
        config = @job.send(:resolve_whatsapp_config, @send_data)
        assert_equal @config, config
      end
    end
  end

  def test_resolve_whatsapp_config_no_config_name
    send_data_without_config = @send_data.dup
    send_data_without_config.delete(:config_name)

    FlowChat::Whatsapp::Configuration.stub(:from_credentials, @config) do
      config = @job.send(:resolve_whatsapp_config, send_data_without_config)
      assert_equal @config, config
    end
  end

  def test_handle_whatsapp_send_error_sends_user_notification
    error = StandardError.new("Test error")

    # Use helper to create mock client that supports send_text
    error_client = BaseTestJob.create_mock_whatsapp_client
    logger = BaseTestJob.create_mock_logger

    FlowChat::Whatsapp::Client.stub(:new, error_client) do
      Rails.stub(:logger, logger) do
        error_raised = assert_raises(StandardError) do
          @job.send(:handle_whatsapp_send_error, error, @send_data, @config)
        end

        assert_equal "Test error", error_raised.message
        # Check that error notification was sent
        assert_equal 1, error_client.sent_messages.length
        assert_equal "+1234567890", error_client.sent_messages.first[0]
      end
    end
  end

  def test_handle_whatsapp_send_error_graceful_failure_on_notification_error
    error = StandardError.new("Test error")

    # Mock client that fails on send_text
    error_client = Object.new
    error_client.define_singleton_method(:send_text) { |phone, text| raise StandardError, "Notification failed" }

    logger = BaseTestJob.create_mock_logger

    FlowChat::Whatsapp::Client.stub(:new, error_client) do
      Rails.stub(:logger, logger) do
        error_raised = assert_raises(StandardError) do
          @job.send(:handle_whatsapp_send_error, error, @send_data, @config)
        end

        assert_equal "Test error", error_raised.message
        # Check that errors were logged
        # rubocop:disable Style/HashSlice
        error_logs = logger.logged_messages.select { |level, msg| level == :error }
        # rubocop:enable Style/HashSlice
        assert error_logs.length >= 2, "Should log original error and notification failure"
      end
    end
  end

  def test_handle_whatsapp_send_error_without_config
    error = StandardError.new("Test error")
    logger = BaseTestJob.create_mock_logger

    Rails.stub(:logger, logger) do
      error_raised = assert_raises(StandardError) do
        @job.send(:handle_whatsapp_send_error, error, @send_data, nil)
      end

      assert_equal "Test error", error_raised.message
      # Check that error was logged
      # rubocop:disable Style/HashSlice
      error_logs = logger.logged_messages.select { |level, msg| level == :error }
      # rubocop:enable Style/HashSlice
      assert error_logs.length >= 1, "Should log the error"
    end
  end

  def test_logging_on_successful_send
    api_result = {"messages" => [{"id" => "msg_123"}]}
    logger = BaseTestJob.create_mock_logger

    FlowChat::Whatsapp::Configuration.stub(:exists?, true) do
      FlowChat::Whatsapp::Configuration.stub(:get, @config) do
        FlowChat::Whatsapp::Client.stub(:new, @mock_client) do
          @mock_client.expect(:send_message, api_result, ["+1234567890", [:text, "Hello, World!", {}]])

          Rails.stub(:logger, logger) do
            @job.perform(@send_data)
          end

          # Check that success was logged
          # rubocop:disable Style/HashSlice
          info_logs = logger.logged_messages.select { |level, msg| level == :info }
          # rubocop:enable Style/HashSlice
          assert info_logs.length >= 1, "Should log success message"
          assert info_logs.any? { |level, msg| msg.include?("msg_123") }, "Should log message ID"
          @mock_client.verify
        end
      end
    end
  end

  def test_logging_on_failed_send
    logger = BaseTestJob.create_mock_logger

    FlowChat::Whatsapp::Configuration.stub(:exists?, true) do
      FlowChat::Whatsapp::Configuration.stub(:get, @config) do
        FlowChat::Whatsapp::Client.stub(:new, @mock_client) do
          @mock_client.expect(:send_message, nil, ["+1234567890", [:text, "Hello, World!", {}]])

          Rails.stub(:logger, logger) do
            assert_raises(RuntimeError) do
              @job.perform(@send_data)
            end
          end

          # Check that failure was logged
          # rubocop:disable Style/HashSlice
          error_logs = logger.logged_messages.select { |level, msg| level == :error }
          # rubocop:enable Style/HashSlice
          assert error_logs.length >= 1, "Should log error message"
          assert error_logs.any? { |level, msg| msg.include?("+1234567890") }, "Should log phone number"
          @mock_client.verify
        end
      end
    end
  end
end
