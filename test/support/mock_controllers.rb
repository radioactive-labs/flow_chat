module FlowChat
  module TestSupport
    # Shared mock controller builders for gateway tests
    module MockControllers
      def build_mock_http_controller(params: {}, method: "POST")
        request = OpenStruct.new(
          params: params.with_indifferent_access,
          method: method,
          headers: OpenStruct.new({"Content-Type" => "application/json"}),
          host: "test.example.com",
          path: "/test",
          remote_ip: "127.0.0.1",
          body: nil,
          cookies: {}
        )

        request.define_singleton_method(:get?) { self.method.upcase == "GET" }
        request.define_singleton_method(:post?) { self.method.upcase == "POST" }
        request.define_singleton_method(:user_agent) { headers["User-Agent"] }

        build_controller_with_request(request)
      end

      def build_mock_ussd_controller(session_id: "session_123", msisdn: "233200000000", userdata: "")
        params = {
          "USERID" => session_id,
          "MSISDN" => msisdn,
          "USERDATA" => userdata
        }

        request = OpenStruct.new(params: params.with_indifferent_access)
        build_controller_with_request(request)
      end

      def build_mock_whatsapp_controller(webhook_body:)
        body_json = webhook_body.is_a?(String) ? webhook_body : webhook_body.to_json
        body_io = StringIO.new(body_json)

        request = OpenStruct.new
        request.define_singleton_method(:post?) { true }
        request.define_singleton_method(:get?) { false }
        request.define_singleton_method(:body) { StringIO.new(body_json) }
        request.define_singleton_method(:headers) { {} }
        request.define_singleton_method(:raw_post) { body_json }
        request.define_singleton_method(:request_method) { "POST" }
        request.define_singleton_method(:path) { "/webhook" }

        build_controller_with_request(request)
      end

      def build_mock_intercom_controller(webhook_body:)
        body_json = webhook_body.is_a?(String) ? webhook_body : webhook_body.to_json
        body_io = StringIO.new(body_json)

        request = OpenStruct.new
        request.define_singleton_method(:post?) { true }
        request.define_singleton_method(:head?) { false }
        request.define_singleton_method(:body) { StringIO.new(body_json) }
        request.define_singleton_method(:headers) { {} }
        request.define_singleton_method(:raw_post) { body_json }
        request.define_singleton_method(:request_method) { "POST" }
        request.define_singleton_method(:path) { "/webhook" }

        build_controller_with_request(request)
      end

      # Webhook payload builders
      def whatsapp_text_message_payload(text:, from: "233200000000", message_id: "wamid.test123", phone_number_id: "123456")
        {
          "entry" => [{
            "changes" => [{
              "value" => {
                "metadata" => {"phone_number_id" => phone_number_id},
                "messages" => [{
                  "from" => from,
                  "id" => message_id,
                  "timestamp" => Time.now.to_i.to_s,
                  "type" => "text",
                  "text" => {"body" => text}
                }],
                "contacts" => [{"profile" => {"name" => "Test User"}, "wa_id" => from}]
              }
            }]
          }]
        }
      end

      def whatsapp_media_message_payload(type:, media_id:, mime_type:, from: "233200000000", message_id: nil, **extra_fields)
        message_id ||= "wamid.#{type}_#{media_id}"
        media_data = {"id" => media_id, "mime_type" => mime_type}.merge(extra_fields.stringify_keys)

        {
          "entry" => [{
            "changes" => [{
              "value" => {
                "metadata" => {"phone_number_id" => "123456"},
                "messages" => [{
                  "from" => from,
                  "id" => message_id,
                  "timestamp" => Time.now.to_i.to_s,
                  "type" => type,
                  type => media_data
                }],
                "contacts" => [{"profile" => {"name" => "Test User"}, "wa_id" => from}]
              }
            }]
          }]
        }
      end

      def whatsapp_contact_message_payload(contact_name:, phone_number:, from: "233200000000", message_id: "wamid.contact123")
        {
          "entry" => [{
            "changes" => [{
              "value" => {
                "metadata" => {"phone_number_id" => "123456"},
                "messages" => [{
                  "from" => from,
                  "id" => message_id,
                  "timestamp" => Time.now.to_i.to_s,
                  "type" => "contacts",
                  "contacts" => [{
                    "name" => {
                      "formatted_name" => contact_name,
                      "first_name" => contact_name.split.first,
                      "last_name" => contact_name.split.last
                    },
                    "phones" => [{"phone" => phone_number, "type" => "MOBILE"}]
                  }]
                }],
                "contacts" => [{"profile" => {"name" => "Test User"}, "wa_id" => from}]
              }
            }]
          }]
        }
      end

      def intercom_user_replied_payload(conversation_id: "conv_123", user_id: "user_456", body: "<p>hello</p>")
        {
          "type" => "notification_event",
          "topic" => "conversation.user.replied",
          "data" => {
            "item" => {
              "type" => "conversation",
              "id" => conversation_id,
              "user" => {"id" => user_id, "name" => "Test User"},
              "conversation_parts" => {
                "conversation_parts" => [{
                  "body" => body,
                  "author" => {"type" => "user", "id" => user_id}
                }]
              }
            }
          }
        }
      end

      private

      def build_controller_with_request(request)
        controller = Object.new
        controller.instance_variable_set(:@request, request)
        controller.instance_variable_set(:@rendered_response, nil)
        controller.instance_variable_set(:@last_head_status, nil)

        controller.define_singleton_method(:request) { @request }
        controller.define_singleton_method(:rendered_response) { @rendered_response }
        controller.define_singleton_method(:last_head_status) { @last_head_status }

        controller.define_singleton_method(:render) do |options|
          @rendered_response = options
          nil
        end

        controller.define_singleton_method(:head) do |status|
          @last_head_status = status
          nil
        end

        # Add response with mock stream for gateways that need it
        mock_response = FlowChat::TestSupport::MockResponse.new
        controller.define_singleton_method(:response) { mock_response }

        controller
      end
    end
  end
end
