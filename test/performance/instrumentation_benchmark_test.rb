# Performance benchmarks for the instrumentation system
# Run with: ruby test/performance/instrumentation_benchmark_test.rb
require "test_helper"
require "benchmark"

module FlowChat
  module Performance
    class InstrumentationBenchmarkTest < Minitest::Test
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

      def test_performance_impact
        skip "Performance tests are unreliable in CI environments" if ENV["CI"] || ENV["GITHUB_ACTIONS"]

        # Measure performance impact of instrumentation
        processor_class = Class.new do
          include FlowChat::Instrumentation

          def process_with_instrumentation
            instrument("test.process", {data: "test"}) do
              # Simulate some work
              sum = 0
              100.times { |i| sum += i }
              sum
            end
          end

          def process_without_instrumentation
            # Same work without instrumentation
            sum = 0
            100.times { |i| sum += i }
            sum
          end
        end

        processor = processor_class.new
        iterations = 10_000

        # Warmup
        100.times do
          processor.process_with_instrumentation
          processor.process_without_instrumentation
        end

        # Benchmark
        time_with = Benchmark.realtime do
          iterations.times { processor.process_with_instrumentation }
        end

        time_without = Benchmark.realtime do
          iterations.times { processor.process_without_instrumentation }
        end

        overhead_percentage = ((time_with - time_without) / time_without) * 100

        puts "\nInstrumentation Performance Results:"
        puts "  Without instrumentation: #{(time_without * 1000).round(2)}ms"
        puts "  With instrumentation: #{(time_with * 1000).round(2)}ms"
        puts "  Overhead: #{overhead_percentage.round(2)}%"

        # Assert overhead is reasonable (less than 100%)
        assert overhead_percentage < 100, "Instrumentation overhead (#{overhead_percentage}%) should be less than 100%"
      end
    end
  end
end
