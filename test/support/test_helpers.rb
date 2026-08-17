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

      # Builds a context wired to run a Meta::MessagingGateway subclass
      # directly against a webhook body, without a real controller or
      # request. Mirrors create_context_with_request from
      # test/unit/whatsapp/gateway/cloud_api_test.rb: an OpenStruct request
      # with post?/get?, a rewindable body, headers and cookies, and a
      # controller that records render/head calls.
      # Subscribes to the real ActiveSupport::Notifications channels rather
      # than stubbing a gateway's #instrument method.
      #
      # That distinction matters and is the reason this helper exists: the
      # clients used to publish message.sent from inside their own send, so a
      # stub on the gateway saw nothing and a test could pass while every
      # subscriber - FlowChat's own MetricsCollector included - counted a
      # successful send twice and a refused one once.
      #
      # @return [Array<Array, Array>] the message.sent and
      #   message.delivery_failed events published while the block ran
      def capture_delivery_events
        sent = []
        failed = []
        subscriptions = [
          ActiveSupport::Notifications.subscribe("message.sent.flow_chat") { |*args| sent << ActiveSupport::Notifications::Event.new(*args) },
          ActiveSupport::Notifications.subscribe("message.delivery_failed.flow_chat") { |*args| failed << ActiveSupport::Notifications::Event.new(*args) }
        ]

        yield

        [sent, failed]
      ensure
        subscriptions&.each { |subscription| ActiveSupport::Notifications.unsubscribe(subscription) }
      end

      def build_messaging_context(body, headers: {}, cookies: {}, params: {})
        context = FlowChat::Context.new

        request = OpenStruct.new(headers: headers, cookies: cookies, params: params)
        request.define_singleton_method(:get?) { false }
        request.define_singleton_method(:post?) { true }
        request.define_singleton_method(:body) do
          StringIO.new(body.is_a?(String) ? body : body.to_json)
        end

        controller = OpenStruct.new(request: request)

        controller.define_singleton_method(:render) do |options|
          @last_render = options
        end
        controller.define_singleton_method(:last_render) { @last_render }

        controller.define_singleton_method(:head) do |status, options = {}|
          @last_head_status = status
          @last_head_options = options
        end
        controller.define_singleton_method(:last_head_status) { @last_head_status }

        context["controller"] = controller
        context
      end

      # Subscribes to a single flow_chat event for the duration of the block
      # and returns every payload published during it.
      def capture_events(event_name)
        events = []
        subscription = ActiveSupport::Notifications.subscribe("#{event_name}.flow_chat") do |*args|
          events << ActiveSupport::Notifications::Event.new(*args).payload
        end

        yield

        events
      ensure
        ActiveSupport::Notifications.unsubscribe(subscription) if subscription
      end

      def capture_webhook_received(&block)
        capture_events(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED, &block)
      end
    end
  end
end
