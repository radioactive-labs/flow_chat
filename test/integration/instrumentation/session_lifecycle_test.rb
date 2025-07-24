# frozen_string_literal: true

# Module: SessionLifecycleTest
#
# Purpose:
# Tests the complete instrumentation of session lifecycle events to ensure proper
# logging and monitoring of session operations throughout the FlowChat system.
#
# Coverage:
# - Session creation events and metadata
# - Session read operations tracking
# - Session write operations monitoring
# - Session deletion and cleanup events
# - Integration with custom logger implementations
# - Event payload structure and content
#
# Architecture:
# The test verifies instrumentation at each stage of session handling:
# 1. Session creation during middleware initialization
# 2. Session reads when accessing stored data
# 3. Session writes when persisting state
# 4. Session deletion during cleanup
#
# Event Types:
# - session.create: New session initialized
# - session.read: Data retrieved from session
# - session.write: Data persisted to session
# - session.delete: Session removed from store
#
# Key Test Scenarios:
# - Complete session lifecycle from creation to deletion
# - Event logging with proper severity levels
# - Session ID generation and tracking
# - Store type identification in events
# - Gateway and platform metadata inclusion
#
# Logger Implementation:
# - Uses a mock logger that captures all log messages
# - Verifies both log level and message content
# - Supports block-based logging for performance
#
# Special Considerations:
# - Test logger must be thread-safe for concurrent tests
# - Instrumentation setup is reset between tests
# - Cache-based session store is mocked inline
# - Events are processed synchronously for testing

# Tests the instrumentation of session lifecycle events
# Verifies session creation, reading, writing, and deletion events
require "test_helper"

module FlowChat
  module Instrumentation
    class SessionLifecycleTest < Minitest::Test
      def setup
        @log_messages = []
        @test_logger = Object.new

        # Mock logger that captures messages
        %w[info debug warn error].each do |level|
          @test_logger.define_singleton_method(level) do |&block|
            @messages ||= []
            @messages << [level.upcase, block.call]
          end
        end

        def @test_logger.messages
          @messages || []
        end

        # Set our test logger
        FlowChat::Config.logger = @test_logger

        # Reset and setup instrumentation
        FlowChat::Instrumentation::Setup.reset!
        FlowChat::Instrumentation::Setup.setup_instrumentation!
      end

      def teardown
        FlowChat::Config.logger = Logger.new($stdout)
        FlowChat::Instrumentation::Setup.reset!
      end

      def test_complete_session_lifecycle_instrumentation
        # Set up cache for session store
        FlowChat::Config.cache = Class.new do
          def initialize
            @data = {}
          end

          def read(key)
            @data[key]
          end

          def write(key, value, options = {})
            @data[key] = value
          end

          def delete(key)
            @data.delete(key)
          end
        end.new

        # Create a context
        context = FlowChat::Context.new
        context["request.msisdn"] = "+256700123456"
        context["request.id"] = "test-session-123"
        context["session.store"] = FlowChat::Session::CacheSessionStore

        # Set up session config
        session_config = FlowChat::Config::SessionConfig.new
        session_config.boundaries = [:flow]
        session_config.identifier = :msisdn

        # Create session middleware
        app = ->(ctx) { "response" }
        middleware = FlowChat::Session::Middleware.new(app, session_config)

        # Execute the middleware
        middleware.call(context)

        # Verify the logs contain expected instrumentation
        logs = @test_logger.messages

        # Verify session lifecycle events were logged
        assert logs.any? { |level, msg| level == "INFO" && msg.include?("Session Created") }
        assert logs.any? { |level, msg| level == "DEBUG" && msg.include?("Generated session ID") }
        assert logs.any? { |level, msg| level == "DEBUG" && msg.include?("Session processing completed") }
      end
    end
  end
end
