module FlowChat
  module TestSupport
    module TestHelpers
      # Creates a mock session store instance for testing
      # This is used when testing components that need a session store object
      def create_session_store_instance
        Class.new do
          def initialize
            @data = {}
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
        end.new
      end

      # Creates a mock session store class for testing
      # This is used when testing configuration that expects a class not an instance
      def create_session_store_class
        Class.new do
          def initialize(context = nil)
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
        end
      end

      # Creates a mock gateway for testing flow execution
      def create_mock_gateway
        Class.new do
          def initialize(app)
            @app = app
            @session_id = "test_session_#{rand(10000)}"  # Fixed session ID per instance
          end

          def call(context)
            # Set up request context like a real gateway would
            context["request.id"] = @session_id  # Use same session ID throughout test
            context["request.message_id"] = SecureRandom.uuid
            context["request.timestamp"] = Time.current.iso8601
            context["request.gateway"] = :test_gateway
            context["request.network"] = nil
            context["request.msisdn"] = "+256700123456"

            # Return the middleware result directly for testing
            @app.call(context)
          end
        end
      end
    end
  end
end
