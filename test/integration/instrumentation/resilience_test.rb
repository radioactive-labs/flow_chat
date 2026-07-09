# Tests the instrumentation system's resilience to edge cases
# Verifies handling of nil payloads, large payloads, and complex data structures
require "test_helper"

module FlowChat
  module Instrumentation
    class ResilienceTest < Minitest::Test
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

      def test_error_resilience
        # Test module that includes instrumentation
        test_module = Module.new do
          def test_with_nil_payload
            instrument("test.nil_payload", nil) do
              "completed"
            end
          end

          def test_with_large_payload
            large_payload = {data: "x" * 10_000}
            instrument("test.large_payload", large_payload) do
              "completed"
            end
          end

          def test_with_complex_payload
            complex_payload = {
              nested: {
                array: [1, 2, {deep: "value"}],
                circular: nil
              }
            }
            # Create circular reference
            complex_payload[:nested][:circular] = complex_payload

            instrument("test.complex_payload", complex_payload) do
              "completed"
            end
          end
        end

        # Create test instance
        test_class = Class.new
        test_class.include(FlowChat::Instrumentation)
        test_class.include(test_module)
        test_instance = test_class.new

        # Test nil payload - should not crash
        result = test_instance.test_with_nil_payload
        assert_equal "completed", result

        # Test large payload - should handle gracefully
        result = test_instance.test_with_large_payload
        assert_equal "completed", result

        # Test complex/circular payload - should handle without infinite loop
        result = test_instance.test_with_complex_payload
        assert_equal "completed", result

        # The main resilience test is that the calls don't crash with problematic payloads
        # All the above calls completed without throwing exceptions, which proves resilience
      end
    end
  end
end
