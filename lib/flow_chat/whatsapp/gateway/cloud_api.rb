require "net/http"
require "json"

module FlowChat
  module Whatsapp
    # Configuration-related errors
    class ConfigurationError < StandardError; end

    module Gateway
      class CloudApi
        include FlowChat::Instrumentation
        include FlowChat::GatewayAsyncSupport
        include FlowChat::Meta::SignatureValidation
        include FlowChat::Meta::WebhookVerification

        attr_reader :context

        def initialize(app, config = nil)
          @app = app
          @config = config || FlowChat::Whatsapp::Configuration.from_credentials
          @client = FlowChat::Whatsapp::Client.new(@config)

          FlowChat.logger.info { "CloudApi: Initialized WhatsApp Cloud API gateway with phone_number_id: #{@config.phone_number_id}" }
          FlowChat.logger.debug { "CloudApi: Gateway configuration - API base URL: #{FlowChat::Config.whatsapp.api_base_url}" }
        end

        def call(context)
          @context = context
          @controller = context.controller
          request = @controller.request

          FlowChat.logger.debug { "CloudApi: Processing #{request.request_method} request to #{request.path}" }

          # Skip webhook-specific handling in background mode
          unless in_background?
            # Handle webhook verification
            if request.get? && request.params["hub.mode"] == "subscribe"
              FlowChat.logger.info { "CloudApi: Handling webhook verification request" }
              return handle_verification(context)
            end
          end

          # Handle webhook messages
          if request.post?
            FlowChat.logger.info { "CloudApi: Handling webhook message (background: #{in_background?})" }
            return handle_webhook(context)
          end

          FlowChat.logger.warn { "CloudApi: Invalid request method or parameters - returning bad request" }
          @controller.head :bad_request
        end

        # Expose client for out-of-band messaging
        attr_reader :client

        # Configure WhatsApp-specific middleware stack
        def self.configure_middleware_stack(builder, custom_middleware)
          FlowChat.logger.debug { "CloudApi: Configuring WhatsApp middleware stack" }

          builder.use custom_middleware
          FlowChat.logger.debug { "CloudApi: Added custom middleware" }

          builder.use FlowChat::Whatsapp::Middleware::ChoiceMapper
          FlowChat.logger.debug { "CloudApi: Added Whatsapp::Middleware::ChoiceMapper" }
        end

        # What this gateway is, for the shared Meta:: modules. Public because
        # FlowChat::Meta::GatewayIdentity declares them public: a gateway saying
        # which platform it speaks for is not a secret, unlike how it validates a
        # signature. Keeping them here rather than below `private` means every
        # Meta gateway answers these the same way.
        def platform
          :whatsapp
        end

        def platform_label
          "WhatsApp"
        end

        def configuration_error_class
          FlowChat::Whatsapp::ConfigurationError
        end

        private

        def determine_message_handler(context)
          # Use simulator mode if enabled, otherwise always use inline
          if context["simulator_mode"]
            FlowChat.logger.debug { "CloudApi: Using simulator message handler" }
            :simulator
          else
            FlowChat.logger.debug { "CloudApi: Using inline message handler" }
            :inline
          end
        end

        def handle_webhook(context)
          # Parse body
          begin
            parse_request_body(@controller.request)
            FlowChat.logger.debug { "CloudApi: Successfully parsed webhook request body" }
          rescue JSON::ParserError => e
            FlowChat.logger.error { "CloudApi: Failed to parse webhook body: #{e.message}" }
            return @controller.head :bad_request
          end

          # Check for simulator mode parameter in request (before validation)
          # But only enable if valid simulator token is provided
          is_simulator_mode = simulate?(context)
          if is_simulator_mode
            FlowChat.logger.info { "CloudApi: Simulator mode enabled for this request" }
            context["simulator_mode"] = true
          end

          # Validate webhook signature for security (skip for simulator mode and background)
          # Return 200 OK even for invalid signatures to prevent WhatsApp from retrying
          unless in_background? || is_simulator_mode || valid_webhook_signature?(@controller.request)
            FlowChat.logger.warn { "CloudApi: Invalid webhook signature - dropping request" }
            return @controller.head :ok
          end

          FlowChat.logger.debug { "CloudApi: Webhook signature validation passed" }

          # A delivery can carry several accounts and several kinds of change at
          # once, so every entry and every change gets looked at rather than only
          # the first of each.
          entries = @body["entry"]
          unless entries.is_a?(Array) && entries.any?
            FlowChat.logger.debug { "CloudApi: No entry found in webhook body - returning OK" }
            return @controller.head :ok
          end

          # Only one change per delivery can drive a flow, because only one can own
          # the response to this request.
          flow_ran = false

          entries.each do |entry|
            changes = entry["changes"]
            next unless changes.is_a?(Array)

            changes.each do |change|
              value = change["value"]
              next unless value.is_a?(Hash)

              case webhook_field(change, value)
              when "messages"
                # There is no separate `statuses` field to subscribe to: Meta
                # reports delivery status under `messages` as well, in a change
                # carrying `statuses` and no `messages`. Handled before the flow
                # slot is claimed, or a status arriving ahead of a message in the
                # same delivery would spend the slot and drop the message.
                handle_statuses(value) if value["statuses"].present?

                next if value["messages"].blank?

                if flow_ran
                  FlowChat.logger.warn { "CloudApi: A second messages change arrived in the same delivery and was not processed" }
                  next
                end
                flow_ran = true

                case handle_messages(context, value)
                when :rejected then return @controller.head :forbidden
                when :enqueued then return @controller.head :ok
                when :rendered then return nil # simulator already wrote the response
                end
              when "statuses"
                # Only reachable for a payload built without a field name, which
                # our own fixtures do and Meta does not.
                handle_statuses(value)
              else
                # Anything that is not a message or its delivery. Coexistence
                # echoes, contact syncs, imported history, account bans, template
                # approvals: all of it is the application's domain, so it is
                # published rather than interpreted here.
                handle_unmodelled_field(change["field"], value, entry["id"])
              end
            end
          end

          @controller.head :ok
        end

        # Meta names the change in `field`. Older payloads, and the ones our own
        # tests build, leave it out, so fall back to what the value carries.
        def webhook_field(change, value)
          return change["field"] if change["field"].present?
          return "messages" if value["messages"].is_a?(Array) && value["messages"].any?
          return "statuses" if value["statuses"].is_a?(Array) && value["statuses"].any?

          nil
        end

        # Returns what happened, so the caller can decide whether it still owns the
        # response: :rejected, :enqueued, :rendered, :processed or :skipped.
        def handle_messages(context, value)
          message = value["messages"]&.first
          return :skipped unless message

          contact = value["contacts"]&.first

          phone_number = FlowChat::PhoneNumberUtil.to_e164(message["from"])
          message_id = message["id"]
          contact_name = contact&.dig("profile", "name")
          business_phone_number = value.dig("metadata", "display_phone_number")
          business_phone_number_id = value.dig("metadata", "phone_number_id")

          # Validate that webhook is for our configured phone number
          if business_phone_number_id != @config.phone_number_id
            FlowChat.logger.warn { "CloudApi: Webhook received for phone_number_id '#{business_phone_number_id}' but configured for '#{@config.phone_number_id}' - rejecting" }
            return :rejected
          end

          context["request.id"] = phone_number
          context["request.user_id"] = phone_number
          context["request.user_name"] = contact_name if contact_name
          context["request.msisdn"] = phone_number
          context["request.gateway"] = :whatsapp_cloud_api
          context["request.platform"] = :whatsapp
          context["request.message_id"] = message_id
          context["request.timestamp"] = Time.current.iso8601
          context["request.body"] = @body

          context["whatsapp.business.phone_number"] = FlowChat::PhoneNumberUtil.to_e164(business_phone_number)
          context["whatsapp.business.phone_number_id"] = business_phone_number_id
          context["whatsapp.client"] = @client

          # Extract message content based on type
          extract_message_content!(message, context)

          if inbound_message?(context)
            # Use instrumentation for message received
            instrument(Events::MESSAGE_RECEIVED, {
              from: phone_number,
              message: context.input,
              message_type: message["type"],
              message_id: message_id
            })
          end

          FlowChat.logger.debug { "CloudApi: Message content extracted - Type: #{message["type"]}, Input: '#{context.input}'" }

          # Determine routing: async enqueue, background execute, or inline
          if should_enqueue_async?
            # Webhook with async enabled → enqueue job and return immediately
            enqueue_async_job
            return :enqueued
          end

          # Background OR inline → process message
          case determine_message_handler(context)
          when :inline
            handle_message_inline(context, @controller)
            :processed
          when :simulator
            handle_message_simulator(context, @controller)
            :rendered
          end
        end

        def handle_statuses(value)
          statuses = value["statuses"]
          return if statuses.blank?

          FlowChat.logger.info { "CloudApi: Received #{statuses.size} status update(s)" }
          FlowChat.logger.debug { "CloudApi: Status updates: #{statuses.inspect}" }

          statuses.each do |status|
            instrument(Events::MESSAGE_STATUS, {
              platform: :whatsapp,
              gateway: :whatsapp_cloud_api,
              business_phone_number_id: value.dig("metadata", "phone_number_id"),
              message_id: status["id"],
              recipient: status["recipient_id"],
              status: status["status"],
              timestamp: status["timestamp"],
              errors: status["errors"],
              # Meta reports more about a delivery than a status and a time: what
              # it billed the conversation as, and its own view of the window.
              # None of it is this gem's business to interpret, and all of it is
              # gone if the named keys are the only way through.
              value: status
            })
          end
        end

        # Everything that is not a message or its delivery. Verified, named, and
        # handed on whole for the application to make sense of.
        #
        # The account id comes from the entry rather than the value because a change
        # about the account itself names no phone number: a ban, a review outcome, a
        # template approval. Without it those arrive identifying nothing, and an
        # application holding several businesses cannot tell whose they are.
        def handle_unmodelled_field(field, value, business_account_id)
          FlowChat.logger.info {
            "CloudApi: Publishing webhook field '#{field}' (value keys: #{value.keys.join(", ")})"
          }

          instrument(Events::WEBHOOK_RECEIVED, {
            platform: :whatsapp,
            gateway: :whatsapp_cloud_api,
            field: field,
            business_account_id: business_account_id,
            business_phone_number: value.dig("metadata", "display_phone_number"),
            business_phone_number_id: value.dig("metadata", "phone_number_id"),
            value: value
          })
        end

        def extract_message_content!(message, context)
          message_type = message["type"]
          FlowChat.logger.debug { "CloudApi: Extracting content from #{message_type} message" }

          case message_type
          when "text"
            content = message.dig("text", "body")
            context.input = content.presence || ""
            FlowChat.logger.debug { "CloudApi: Text message content: '#{content}'" }
          when "interactive"
            # Handle button/list replies
            if message.dig("interactive", "type") == "button_reply"
              content = message.dig("interactive", "button_reply", "id")
              context.input = content
              FlowChat.logger.debug { "CloudApi: Button reply ID: '#{content}'" }
            elsif message.dig("interactive", "type") == "list_reply"
              content = message.dig("interactive", "list_reply", "id")
              context.input = content
              FlowChat.logger.debug { "CloudApi: List reply ID: '#{content}'" }
            end
          when "location"
            location = {
              latitude: message.dig("location", "latitude"),
              longitude: message.dig("location", "longitude"),
              name: message.dig("location", "name"),
              address: message.dig("location", "address")
            }
            context["request.location"] = location
            context.input = ""
            FlowChat.logger.debug { "CloudApi: Location received - Lat: #{location[:latitude]}, Lng: #{location[:longitude]}" }
          when "image", "document", "audio", "video", "sticker"
            media_data = message[message["type"]]
            context["request.media"] = {
              type: message["type"].to_sym,
              id: media_data["id"],
              mime_type: media_data["mime_type"],
              caption: media_data["caption"],
              filename: media_data["filename"],
              sha256: media_data["sha256"],
              animated: media_data["animated"]
            }
            # The caption (if any) is the turn's text; a text-less media message has blank input.
            context.input = media_data["caption"].presence || ""
            FlowChat.logger.debug { "CloudApi: Media received - Type: #{message["type"]}, ID: #{media_data["id"]}" }
          when "contacts"
            # WhatsApp sends contacts as an array, take the first one
            contact_data = message.dig("contacts", 0)
            if contact_data
              phones = contact_data.dig("phones") || []
              context["request.contact"] = {
                name: contact_data.dig("name", "formatted_name"),
                first_name: contact_data.dig("name", "first_name"),
                last_name: contact_data.dig("name", "last_name"),
                phones: phones.map { |p| p["phone"] },
                phone_number: phones.first&.dig("phone")
              }
              context.input = ""
              FlowChat.logger.debug { "CloudApi: Contact received - Name: #{context["request.contact"][:name]}" }
            end
          end
        end

        def handle_message_inline(context, controller)
          response = @app.call(context)
          if response
            type, prompt, choices, media = response
            result = report_delivery_failure(
              context,
              to: context["request.msisdn"],
              session_id: context["request.id"],
              message: prompt,
              message_type: (type == :prompt) ? "prompt" : "terminal",
              gateway: :whatsapp_cloud_api,
              platform: :whatsapp
            ) do
              @client.send_message(context["request.msisdn"], prompt, choices: choices, media: media)
            end
            context["whatsapp.message_result"] = result

            # Instrument message sent
            instrument(Events::MESSAGE_SENT, {
              to: context["request.msisdn"],
              session_id: context["request.id"],
              message: prompt,
              message_type: (type == :prompt) ? "prompt" : "terminal",
              gateway: :whatsapp_cloud_api,
              platform: :whatsapp,
              content_length: prompt.to_s.length,
              # What Meta called it, so this and message.status can be joined.
              platform_message_id: platform_message_id_from(result),
              timestamp: context["request.timestamp"]
            })
          end
        end

        # Meta answers a send with the ids it assigned.
        def platform_message_id_from(result)
          return nil unless result.is_a?(Hash)

          result.dig("messages", 0, "id")
        end

        def handle_message_simulator(context, controller)
          response = @app.call(context)

          if response
            _, prompt, choices, media = response
            response_data = render_response(prompt, choices, media)

            # For simulator mode, return the response data in the HTTP response
            # instead of actually sending via WhatsApp API
            message_payload = @client.build_message_payload(response_data, context["request.msisdn"])

            simulator_response = {
              mode: "simulator",
              webhook_processed: true,
              would_send: message_payload,
              message_info: {
                to: context["request.msisdn"],
                contact_name: context["request.user_name"],
                timestamp: Time.now.iso8601
              }
            }

            controller.render json: simulator_response
            nil
          end
        end

        def simulate?(context)
          # Check if simulator mode is enabled for this processor
          return false unless context["enable_simulator"]

          # Then check if simulator mode is requested and authorized
          @body.dig("simulator_mode") &&
            FlowChat::Security.valid_simulator_cookie?(@controller.request.cookies[FlowChat::Security::SIMULATOR_COOKIE_NAME])
        end

        def parse_request_body(request)
          return @body if @body

          if request.body.nil?
            FlowChat.logger.debug { "CloudApi: Request body is nil, returning empty hash" }
            @body = {}
          else
            request.body.rewind if request.body.respond_to?(:rewind)
            @body = JSON.parse(request.body.read)
          end
        end

        def render_response(prompt, choices, media)
          FlowChat::Whatsapp::Renderer.new(prompt, choices: choices, media: media).render
        end
      end
    end
  end
end
