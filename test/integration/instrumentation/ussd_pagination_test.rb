# Tests the instrumentation of USSD pagination flows
# Verifies pagination events and state management
require "test_helper"

module FlowChat
  module Instrumentation
    class UssdPaginationTest < Minitest::Test
      def setup
        @log_messages = []
        @test_logger = Object.new

        # Mock logger that captures messages
        %w[info debug warn error].each do |level|
          @test_logger.define_singleton_method(level) do |&block|
            @messages ||= []
            msg = block ? block.call : ""
            @messages << [level.upcase, msg]
          end
        end

        # Add the 'add' method that Logger uses
        @test_logger.define_singleton_method(:add) do |severity, message = nil, progname = nil, &block|
          @messages ||= []
          msg = message || (block ? block.call : progname)
          level = case severity
          when 0 then "DEBUG"
          when 1 then "INFO"
          when 2 then "WARN"
          when 3 then "ERROR"
          else "UNKNOWN"
          end
          @messages << [level, msg.to_s]
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

      def test_ussd_pagination_flow
        # Create flow with paginated list
        pagination_flow = Class.new(FlowChat::Flow) do
          def self.name
            "PaginationTestFlow"
          end

          def start
            # Create many items to trigger automatic pagination
            items = (1..20).map { |i| ["Item #{i}", "item_#{i}"] }

            selected = app.screen("paginated_list") do |prompt|
              # select doesn't support per_page, but USSD middleware will paginate automatically
              # if the rendered content exceeds the page size
              prompt.select "Choose an item:", items
            end

            app.say "You selected: #{selected}"
          end
        end

        # Mock controller
        controller = Object.new
        def controller.params
          {sessionId: "test123", text: "98", phoneNumber: "256700123456"}
        end

        def controller.request
          self
        end

        def controller.headers
          {}
        end

        controller.instance_variable_set(:@rendered, nil)

        def controller.render(options)
          @rendered = options
        end

        def controller.rendered
          @rendered
        end

        # Create a simple mock session store class
        mock_session_store = Class.new do
          def initialize(context)
            @data = {}
          end

          def get(key)
            @data[key]
          end

          def set(key, value)
            @data[key] = value
          end

          def delete(key)
            @data.delete(key)
          end
        end

        # Create processor
        processor = FlowChat::Processor.new(controller) do |config|
          config.use_gateway FlowChat::Ussd::Gateway::Nalo
          config.use_session_store mock_session_store
        end

        # Run flow (simulating pagination navigation)
        processor.run(pagination_flow, :start)

        # Check instrumentation
        logs = @test_logger.messages

        # Verify USSD-specific instrumentation - check for USSD gateway logs
        assert logs.any? { |level, msg| msg.include?("Ussd::Gateway::Nalo") || msg.include?("USSD Message") },
          "Should have USSD-specific logs"

        # Verify pagination was triggered
        assert logs.any? { |level, msg| msg.include?("USSD Pagination Triggered") },
          "Should have pagination triggered log"

        # Verify pagination was handled
        rendered = controller.rendered
        assert rendered, "Should have rendered response"
        assert rendered[:json], "Should have JSON response"
        assert rendered[:json][:MSG], "Should have MSG in JSON response"
        assert rendered[:json][:MSG].include?("# More") || rendered[:json][:MSG].include?("#. More"),
          "Should show 'More' option in: #{rendered[:json][:MSG]}"
        assert rendered[:json][:MSG].include?("Choose an item:"), "Should show prompt"

        # Verify proper session handling
        assert logs.any? { |level, msg| msg.include?("Session") }, "Should have session-related logs"
      end
    end
  end
end
