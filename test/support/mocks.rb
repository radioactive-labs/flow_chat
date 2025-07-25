module FlowChat
  module TestSupport
    # Mock response stream for testing streaming functionality
    class MockResponseStream
      def initialize
        @written_data = []
      end

      def write(data)
        @written_data << data
      end

      def close
        # No-op for testing
      end

      attr_reader :written_data
    end

    # Mock response object with streaming support
    class MockResponse
      attr_accessor :headers

      def initialize
        @headers = {}
        @stream = MockResponseStream.new
      end

      attr_reader :stream
    end

    # Simple mock class that supports both instance_variable_set and expect methods
    # Used primarily for testing Intercom gateway interactions
    class SimpleMock
      def initialize
        @expectations = {}
        @return_values = {}
        @response = MockResponse.new
      end

      attr_reader :response

      def expect(method_name, return_value, args = [])
        @expectations[method_name] = {return_value: return_value, args: args}
        return_value
      end

      def method_missing(method_name, *args)
        if @expectations.key?(method_name)
          @expectations[method_name][:return_value]
        elsif method_name.to_s.end_with?("?")
          # Default HTTP method queries to false
          false
        elsif method_name.to_s.end_with?("=")
          # Handle setter methods
          attr_name = "@#{method_name.to_s.chomp("=")}"
          instance_variable_set(attr_name, args.first)
        elsif method_name == :head
          # Mock Rails controller head method
          nil
        elsif method_name == :render
          # Mock Rails controller render method
          nil
        elsif method_name == :==
          # Handle equality comparison
          args.first == self
        elsif method_name == :app_id
          # Return a default app_id for logging
          "mock_app_id"
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        @expectations.key?(method_name) ||
          method_name.to_s.end_with?("?") ||
          method_name.to_s.end_with?("=") ||
          method_name == :head ||
          method_name == :render ||
          method_name == :== ||
          method_name == :app_id ||
          super
      end
    end
  end
end
