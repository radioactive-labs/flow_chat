require "json"

module FlowChat
  module Meta
    # The Messenger Platform envelope, shared by Facebook Messenger and
    # Instagram DMs. Both deliver entry[].messaging[] and both send through the
    # same Send API, so the envelope is implemented once and each platform
    # supplies only what actually differs.
    class MessagingGateway
      include FlowChat::Instrumentation
      include FlowChat::GatewayAsyncSupport
      include FlowChat::Meta::SignatureValidation
      include FlowChat::Meta::WebhookVerification

      attr_reader :context, :client

      def initialize(app, config = nil)
        @app = app
        @config = config || configuration_class.from_credentials
        @client = client_class.new(@config)

        FlowChat.logger.info { "#{log_tag}: Initialized #{platform} gateway for account #{@config.account_id}" }
      end

      def call(context)
        @context = context
        @controller = context.controller
        request = @controller.request

        unless in_background?
          if request.get? && request.params["hub.mode"] == "subscribe"
            return handle_verification(context)
          end
        end

        return handle_webhook(context) if request.post?

        FlowChat.logger.warn { "#{log_tag}: Invalid request method or parameters - returning bad request" }
        @controller.head :bad_request
      end

      def self.configure_middleware_stack(builder, custom_middleware)
        builder.use custom_middleware
        builder.use choice_mapper_class
      end

      # --- Hooks each platform overrides ---

      def gateway_name
        raise NotImplementedError
      end

      def configuration_class
        raise NotImplementedError
      end

      def client_class
        raise NotImplementedError
      end

      def renderer_class
        raise NotImplementedError
      end

      # Meta names the subscription this delivery came from. Messenger uses
      # "page". Instagram's value depends on how the app is set up, so each
      # platform states its own rather than sharing a guess.
      def expected_webhook_object
        "page"
      end

      private

      def handle_webhook(context)
        begin
          parse_request_body(@controller.request)
        rescue JSON::ParserError => e
          FlowChat.logger.error { "#{log_tag}: Failed to parse webhook body: #{e.message}" }
          return @controller.head :bad_request
        end

        is_simulator_mode = simulate?(context)
        context["simulator_mode"] = true if is_simulator_mode

        unless in_background? || is_simulator_mode || valid_webhook_signature?(@controller.request)
          FlowChat.logger.warn { "#{log_tag}: Invalid webhook signature - dropping request" }
          return @controller.head :ok
        end

        # Warn rather than debug. A gateway whose expected_webhook_object does not
        # match what the app is actually subscribed to drops every delivery here
        # and answers 200, so the symptom is a bot that receives nothing while the
        # dashboard reports successful deliveries. That is worth a line in
        # production logs, not one only visible at debug level.
        if @body["object"].present? && @body["object"] != expected_webhook_object
          FlowChat.logger.warn {
            "#{log_tag}: Ignoring webhook for object '#{@body["object"]}', expected " \
            "'#{expected_webhook_object}'. If every delivery lands here, this gateway's " \
            "expected_webhook_object does not match the app's webhook subscription."
          }
          return @controller.head :ok
        end

        entries = @body["entry"]
        unless entries.is_a?(Array) && entries.any?
          return @controller.head :ok
        end

        # Only one event per delivery can drive a flow, because only one can own
        # the response to this request.
        flow_ran = false

        entries.each do |entry|
          events = entry["messaging"] || entry["standby"]
          next unless events.is_a?(Array)

          # Receipts are handled before any flow claims the slot. A receipt
          # arriving ahead of a message in the same batch would otherwise spend
          # the slot and the message would be lost.
          events.each { |event| handle_status(entry, event) if status_event?(event) }

          events.each do |event|
            next if status_event?(event)

            if echo?(event)
              publish_echo(entry, event)
              next
            end

            unless drives_flow?(event)
              publish_unmodelled(entry, event)
              next
            end

            if flow_ran
              FlowChat.logger.warn { "#{log_tag}: A second message arrived in the same delivery and was not processed" }
              next
            end
            flow_ran = true

            case handle_message(context, entry, event)
            when :rejected then return @controller.head :forbidden
            when :enqueued then return @controller.head :ok
            when :rendered then return nil
            end
          end
        end

        @controller.head :ok
      end

      def status_event?(event)
        event.key?("delivery") || event.key?("read")
      end

      def echo?(event)
        event.dig("message", "is_echo") == true
      end

      def drives_flow?(event)
        event.key?("message") || event.key?("postback")
      end

      def handle_message(context, entry, event)
        account_id = entry["id"]
        unless @config.account_ids.map(&:to_s).include?(account_id.to_s)
          FlowChat.logger.warn { "#{log_tag}: Webhook for account '#{account_id}' but configured for #{@config.account_ids.inspect} - rejecting" }
          return :rejected
        end

        sender_id = event.dig("sender", "id")
        message = event["message"] || event["postback"]

        context["request.id"] = sender_id
        context["request.user_id"] = sender_id
        context["request.msisdn"] = nil
        context["request.message_id"] = message["mid"]
        context["request.gateway"] = gateway_name
        context["request.platform"] = platform
        context["request.timestamp"] = Time.current.iso8601
        context["request.body"] = @body

        context["#{platform}.account.id"] = account_id
        context["#{platform}.client"] = @client

        extract_message_content!(event, context)

        instrument(FlowChat::Instrumentation::Events::MESSAGE_RECEIVED, {
          from: sender_id,
          message: context.input,
          message_type: event.key?("postback") ? "postback" : "message",
          message_id: message["mid"]
        })

        if should_enqueue_async?
          enqueue_async_job
          return :enqueued
        end

        if context["simulator_mode"]
          handle_message_simulator(context)
          :rendered
        else
          handle_message_inline(context)
          :processed
        end
      end

      # A postback's payload, a quick reply's payload, and otherwise the text.
      # An attachment-only turn has blank input, matching the media contract the
      # other gateways follow.
      def extract_message_content!(event, context)
        if event.key?("postback")
          context.input = event.dig("postback", "payload").to_s
          return
        end

        message = event["message"]

        if message["quick_reply"]
          context.input = message.dig("quick_reply", "payload").to_s
          return
        end

        attachments = message["attachments"]
        if attachments.is_a?(Array) && attachments.any?
          attachment = attachments.first

          # Meta delivers a shared location as an attachment like any image, but
          # every other gateway here puts one on request.location, and a flow
          # reading app.location should not have to know which platform it is on.
          if attachment["type"].to_s == "location"
            coordinates = attachment.dig("payload", "coordinates") || {}
            context["request.location"] = {
              latitude: coordinates["lat"],
              longitude: coordinates["long"],
              name: attachment["title"]
            }.compact
          else
            context["request.media"] = {
              type: normalize_attachment_type(attachment["type"]),
              url: attachment.dig("payload", "url")
            }
          end
        end

        context.input = message["text"].presence || ""
      end

      # "file" is Meta's name for what every other gateway here calls a document.
      def normalize_attachment_type(type)
        case type.to_s
        when "file" then :document
        when "" then nil
        else type.to_s.to_sym
        end
      end

      def handle_status(entry, event)
        %w[delivery read].each do |kind|
          payload = event[kind]
          next unless payload

          instrument(FlowChat::Instrumentation::Events::MESSAGE_STATUS, {
            platform: platform,
            gateway: gateway_name,
            account_id: entry["id"],
            recipient: event.dig("sender", "id"),
            status: kind,
            timestamp: event["timestamp"],
            value: payload
          })
        end
      end

      # An echo reports a message sent on this thread by someone other than the
      # user. Which someone decides what the application does about it: a human
      # replying from the page inbox usually means the flow should stand down.
      def publish_echo(entry, event)
        instrument(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED, {
          platform: platform,
          gateway: gateway_name,
          field: "message_echoes",
          account_id: entry["id"],
          echo_origin: echo_origin(event),
          value: event
        })
      end

      def echo_origin(event)
        app_id = event.dig("message", "app_id")

        return :human_agent if app_id.blank?
        return :self if app_id.to_s == @config.app_id.to_s

        :other_app
      end

      # Everything that is not a message, its receipt, or an echo. Reactions,
      # referrals, opt-ins, handovers, policy enforcement: all of it is the
      # application's domain, so it is published whole rather than interpreted.
      def publish_unmodelled(entry, event)
        field = (event.keys - %w[sender recipient timestamp]).first

        FlowChat.logger.info { "#{log_tag}: Publishing webhook event '#{field}'" }

        instrument(FlowChat::Instrumentation::Events::WEBHOOK_RECEIVED, {
          platform: platform,
          gateway: gateway_name,
          field: field,
          account_id: entry["id"],
          value: event
        })
      end

      def handle_message_inline(context)
        response = @app.call(context)
        return unless response

        type, prompt, choices, media = response

        result = report_delivery_failure(
          context,
          to: context["request.user_id"],
          session_id: context["request.id"],
          message: prompt,
          message_type: (type == :prompt) ? "prompt" : "terminal",
          gateway: gateway_name,
          platform: platform
        ) do
          @client.send_message(context["request.user_id"], prompt, choices: choices, media: media)
        end

        context["#{platform}.message_result"] = result

        instrument(FlowChat::Instrumentation::Events::MESSAGE_SENT, {
          to: context["request.user_id"],
          session_id: context["request.id"],
          message: prompt,
          message_type: (type == :prompt) ? "prompt" : "terminal",
          gateway: gateway_name,
          platform: platform,
          content_length: prompt.to_s.length,
          platform_message_id: platform_message_id_from(result),
          timestamp: context["request.timestamp"]
        })
      end

      # The Send API answers with the id it assigned, flatter than WhatsApp's
      # messages[0].id.
      def platform_message_id_from(result)
        return nil unless result.is_a?(Hash)

        result["message_id"]
      end

      def handle_message_simulator(context)
        response = @app.call(context)
        return unless response

        _, prompt, choices, media = response
        rendered = renderer_class.new(prompt, choices: choices, media: media).render

        @controller.render json: {
          mode: "simulator",
          webhook_processed: true,
          would_send: rendered,
          message_info: {
            to: context["request.user_id"],
            timestamp: Time.now.iso8601
          }
        }

        nil
      end

      def simulate?(context)
        return false unless context["enable_simulator"]

        @body.dig("simulator_mode") &&
          FlowChat::Security.valid_simulator_cookie?(@controller.request.cookies[FlowChat::Security::SIMULATOR_COOKIE_NAME])
      end

      def parse_request_body(request)
        return @body if @body

        @body = if request.body.nil?
          {}
        else
          request.body.rewind if request.body.respond_to?(:rewind)
          JSON.parse(request.body.read)
        end
      end
    end
  end
end
