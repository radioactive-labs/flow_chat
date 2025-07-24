module FlowChat
  module TestSupport
    module Factories
      # Create a mock controller for testing
      def mock_controller(options = {})
        controller = Minitest::Mock.new
        request = options[:request] || mock_request(options)
        controller.expect(:request, request)
        controller.expect(:params, options[:params] || {})
        controller.expect(:head, nil, [:ok])
        controller
      end

      # Create a mock request object
      def mock_request(options = {})
        request = Minitest::Mock.new
        request.expect(:headers, options[:headers] || {})
        request.expect(:body, options[:body] || StringIO.new(""))
        request.expect(:raw_post, options[:raw_post] || "")
        request.expect(:request_method, options[:method] || "POST")
        request.expect(:url, options[:url] || "http://example.com")
        request.expect(:query_parameters, options[:query_params] || {})
        request
      end

      # Create webhook payload for WhatsApp
      def whatsapp_webhook_payload(overrides = {})
        {
          "object" => "whatsapp_business_account",
          "entry" => [{
            "id" => "123456789",
            "changes" => [{
              "value" => {
                "messaging_product" => "whatsapp",
                "metadata" => {
                  "display_phone_number" => "15551234567",
                  "phone_number_id" => "123456789"
                },
                "messages" => [{
                  "from" => overrides[:from] || "256700123456",
                  "id" => overrides[:message_id] || "wamid.test123",
                  "timestamp" => overrides[:timestamp] || Time.now.to_i.to_s,
                  "text" => {
                    "body" => overrides[:text] || "Hello"
                  },
                  "type" => "text"
                }]
              }
            }]
          }]
        }.deep_merge(overrides.except(:from, :message_id, :timestamp, :text))
      end

      # Create USSD request parameters
      def ussd_params(overrides = {})
        {
          "sessionId" => overrides[:session_id] || "test_session_123",
          "phoneNumber" => overrides[:phone_number] || "+256700123456",
          "networkCode" => overrides[:network_code] || "MTN",
          "serviceCode" => overrides[:service_code] || "*123#",
          "text" => overrides[:text] || "",
          "gateway" => overrides[:gateway] || "nalo"
        }.merge(overrides.except(:session_id, :phone_number, :network_code, :service_code, :text, :gateway))
      end

      # Create Intercom webhook payload
      def intercom_webhook_payload(overrides = {})
        {
          "type" => overrides[:type] || "conversation.user.replied",
          "app_id" => overrides[:app_id] || "test_app_id",
          "data" => {
            "type" => "conversation",
            "id" => overrides[:conversation_id] || "conv_123",
            "created_at" => overrides[:created_at] || Time.now.to_i,
            "updated_at" => overrides[:updated_at] || Time.now.to_i
          },
          "links" => {},
          "id" => overrides[:id] || "notif_123",
          "topic" => overrides[:topic] || "conversation.user.replied",
          "delivery_status" => "pending",
          "delivery_attempts" => 1,
          "delivered_at" => 0,
          "first_sent_at" => Time.now.to_i,
          "created_at" => Time.now.to_i,
          "self" => nil
        }.deep_merge(overrides.except(:type, :app_id, :conversation_id, :created_at, :updated_at, :id, :topic))
      end

      # Create a mock session data structure
      def session_data(overrides = {})
        {
          current_screen: overrides[:current_screen] || "main",
          current_flow: overrides[:current_flow] || "TestFlow",
          data: overrides[:data] || {},
          _version: overrides[:version] || 1
        }.merge(overrides.except(:current_screen, :current_flow, :data, :version))
      end

      # Create a mock context
      def mock_context(overrides = {})
        context = FlowChat::Context.new

        # Set default request values
        context["request.id"] = overrides[:request_id] || "test_request_123"
        context["request.message_id"] = overrides[:message_id] || SecureRandom.uuid
        context["request.timestamp"] = overrides[:timestamp] || Time.current.iso8601
        context["request.gateway"] = overrides[:gateway] || :test_gateway
        context["request.network"] = overrides[:network] || nil
        context["request.msisdn"] = overrides[:msisdn] || "+256700123456"
        context["request.input"] = overrides[:input] || ""

        # Apply any additional overrides
        overrides.each do |key, value|
          next if [:request_id, :message_id, :timestamp, :gateway, :network, :msisdn, :input].include?(key)
          context[key.to_s] = value
        end

        context
      end
    end
  end
end
