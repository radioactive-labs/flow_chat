require "test_helper"

class LogSubscriberTest < Minitest::Test
  def setup
    @log_messages = []
    @test_logger = Object.new
    
    # Mock logger that captures messages
    def @test_logger.info(&block)
      @messages ||= []
      @messages << ["INFO", block.call]
    end
    
    def @test_logger.debug(&block)
      @messages ||= []
      @messages << ["DEBUG", block.call]
    end
    
    def @test_logger.warn(&block)
      @messages ||= []
      @messages << ["WARN", block.call]
    end
    
    def @test_logger.error(&block)
      @messages ||= []
      @messages << ["ERROR", block.call]
    end
    
    def @test_logger.messages
      @messages || []
    end
    
    # Set our test logger
    FlowChat::Config.logger = @test_logger
    
    @subscriber = FlowChat::Instrumentation::LogSubscriber.new
  end

  def teardown
    FlowChat::Config.logger = Logger.new($stdout)
  end

  def test_flow_execution_start_event
    event = create_event("flow.execution.start.flow_chat", {
      flow_name: "TestFlow",
      action: "welcome",
      session_id: "session_123"
    })
    
    @subscriber.flow_execution_start(event)
    
    messages = @test_logger.messages
    assert_equal 1, messages.size
    level, message = messages.first
    
    assert_equal "INFO", level
    assert_includes message, "Flow Execution Started: TestFlow#welcome"
    assert_includes message, "[Session: session_123]"
  end

  def test_flow_execution_end_event
    event = create_event("flow.execution.end.flow_chat", {
      flow_name: "TestFlow",
      action: "welcome",
      session_id: "session_123"
    }, duration: 150.5)
    
    @subscriber.flow_execution_end(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "INFO", level
    assert_includes message, "Flow Execution Completed: TestFlow#welcome"
    assert_includes message, "(150.5ms)"
    assert_includes message, "[Session: session_123]"
  end

  def test_flow_execution_error_event
    event = create_event("flow.execution.error.flow_chat", {
      flow_name: "TestFlow",
      action: "welcome",
      session_id: "session_123",
      error_class: "StandardError",
      error_message: "Something went wrong"
    }, duration: 75.2)
    
    @subscriber.flow_execution_error(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "ERROR", level
    assert_includes message, "Flow Execution Failed: TestFlow#welcome"
    assert_includes message, "(75.2ms)"
    assert_includes message, "StandardError: Something went wrong"
    assert_includes message, "[Session: session_123]"
  end

  def test_session_created_event
    event = create_event("session.created.flow_chat", {
      session_id: "session_123",
      store_type: "CacheSessionStore",
      gateway: :whatsapp_cloud_api
    })
    
    @subscriber.session_created(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "INFO", level
    assert_includes message, "Session Created: session_123"
    assert_includes message, "[Store: CacheSessionStore, Gateway: whatsapp_cloud_api]"
  end

  def test_session_destroyed_event
    event = create_event("session.destroyed.flow_chat", {
      session_id: "session_123",
      gateway: :whatsapp_cloud_api
    })
    
    @subscriber.session_destroyed(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "INFO", level
    assert_includes message, "Session Destroyed: session_123"
    assert_includes message, "[Gateway: whatsapp_cloud_api]"
  end

  def test_session_cache_hit_event
    event = create_event("session.cache.hit.flow_chat", {
      session_id: "session_123",
      key: "user_data"
    })
    
    @subscriber.session_cache_hit(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "DEBUG", level
    assert_includes message, "Session Cache Hit: session_123 - Key: user_data"
  end

  def test_session_cache_miss_event
    event = create_event("session.cache.miss.flow_chat", {
      session_id: "session_123",
      key: "user_data"
    })
    
    @subscriber.session_cache_miss(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "DEBUG", level
    assert_includes message, "Session Cache Miss: session_123 - Key: user_data"
  end

  def test_session_data_get_event
    event = create_event("session.data.get.flow_chat", {
      session_id: "session_123",
      key: "username",
      value: "john_doe"
    })
    
    @subscriber.session_data_get(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "DEBUG", level
    assert_includes message, "Session Data Get: session_123 - Key: username = \"john_doe\""
  end

  def test_session_data_set_event
    event = create_event("session.data.set.flow_chat", {
      session_id: "session_123",
      key: "username"
    })
    
    @subscriber.session_data_set(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "DEBUG", level
    assert_includes message, "Session Data Set: session_123 - Key: username"
  end

  def test_whatsapp_message_received_event
    event = create_event("whatsapp.message.received.flow_chat", {
      from: "+1234567890",
      message_type: "text",
      message_id: "msg_123",
      contact_name: "John Doe"
    })
    
    @subscriber.whatsapp_message_received(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "INFO", level
    assert_includes message, "WhatsApp Message Received: +1234567890 (John Doe)"
    assert_includes message, "Type: text [ID: msg_123]"
  end

  def test_whatsapp_message_received_without_contact_name
    event = create_event("whatsapp.message.received.flow_chat", {
      from: "+1234567890",
      message_type: "text",
      message_id: "msg_123"
    })
    
    @subscriber.whatsapp_message_received(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "INFO", level
    assert_includes message, "WhatsApp Message Received: +1234567890"
    refute_includes message, "()"  # Should not have empty parentheses
    assert_includes message, "Type: text [ID: msg_123]"
  end

  def test_whatsapp_message_sent_event
    event = create_event("whatsapp.message.sent.flow_chat", {
      to: "+1234567890",
      message_type: "text",
      content_length: 25
    }, duration: 150.0)
    
    @subscriber.whatsapp_message_sent(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "INFO", level
    assert_includes message, "WhatsApp Message Sent: +1234567890"
    assert_includes message, "Type: text (150.0ms)"
    assert_includes message, "[Length: 25 chars]"
  end

  def test_whatsapp_webhook_verified_event
    event = create_event("whatsapp.webhook.verified.flow_chat", {
      challenge: "challenge_123"
    })
    
    @subscriber.whatsapp_webhook_verified(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "INFO", level
    assert_includes message, "WhatsApp Webhook Verified Successfully"
    assert_includes message, "[Challenge: challenge_123]"
  end

  def test_whatsapp_webhook_failed_event
    event = create_event("whatsapp.webhook.failed.flow_chat", {
      reason: "Invalid verify token"
    })
    
    @subscriber.whatsapp_webhook_failed(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "WARN", level
    assert_includes message, "WhatsApp Webhook Verification Failed: Invalid verify token"
  end

  def test_whatsapp_media_upload_success_event
    event = create_event("whatsapp.media.upload.flow_chat", {
      filename: "document.pdf",
      size: 2048576  # 2MB
    }, duration: 500.0)
    
    @subscriber.whatsapp_media_upload(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "INFO", level
    assert_includes message, "WhatsApp Media Upload: document.pdf"
    assert_includes message, "(2.0 MB, 500.0ms)"
    assert_includes message, "Success"
  end

  def test_whatsapp_media_upload_failure_event
    event = create_event("whatsapp.media.upload.flow_chat", {
      filename: "document.pdf",
      success: false,
      error: "File too large"
    }, duration: 100.0)
    
    @subscriber.whatsapp_media_upload(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "ERROR", level
    assert_includes message, "WhatsApp Media Upload Failed: document.pdf"
    assert_includes message, "(100.0ms)"
    assert_includes message, "File too large"
  end

  def test_ussd_message_received_event
    event = create_event("ussd.message.received.flow_chat", {
      from: "+256700000000",
      input: "1",
      session_id: "session_123"
    })
    
    @subscriber.ussd_message_received(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "INFO", level
    assert_includes message, "USSD Message Received: +256700000000"
    assert_includes message, "Input: '1'"
    assert_includes message, "[Session: session_123]"
  end

  def test_ussd_pagination_triggered_event
    event = create_event("ussd.pagination.triggered.flow_chat", {
      current_page: 2,
      total_pages: 5,
      content_length: 320,
      session_id: "session_123"
    })
    
    @subscriber.ussd_pagination_triggered(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "INFO", level
    assert_includes message, "USSD Pagination Triggered: Page 2/5"
    assert_includes message, "(320 chars)"
    assert_includes message, "[Session: session_123]"
  end

  def test_context_created_event
    event = create_event("context.created.flow_chat", {
      gateway: :whatsapp_cloud_api
    })
    
    @subscriber.context_created(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "DEBUG", level
    assert_includes message, "Context Created [Gateway: whatsapp_cloud_api]"
  end

  def test_context_created_event_unknown_gateway
    event = create_event("context.created.flow_chat", {})
    
    @subscriber.context_created(event)
    
    messages = @test_logger.messages
    level, message = messages.first
    
    assert_equal "DEBUG", level
    assert_includes message, "Context Created [Gateway: unknown]"
  end

  def test_format_bytes_helper
    subscriber = FlowChat::Instrumentation::LogSubscriber.new
    
    # Test bytes
    assert_equal "512 bytes", subscriber.send(:format_bytes, 512)
    
    # Test KB
    assert_equal "1.5 KB", subscriber.send(:format_bytes, 1536)  # 1.5 KB
    
    # Test MB
    assert_equal "2.5 MB", subscriber.send(:format_bytes, 2621440)  # 2.5 MB
    
    # Test nil
    assert_equal "unknown size", subscriber.send(:format_bytes, nil)
  end

  private

  def create_event(name, payload, duration: 0.0)
    start_time = Time.current
    finish_time = start_time + (duration / 1000.0)  # duration is in ms
    
    event = Object.new
    event.define_singleton_method(:name) { name }
    event.define_singleton_method(:payload) { payload }
    event.define_singleton_method(:duration) { duration }
    event.define_singleton_method(:time) { start_time }
    event.define_singleton_method(:end) { finish_time }
    
    event
  end
end 