require "json"

module FlowChat
  module Telegram
    class ConfigurationError < StandardError; end

    module Gateway
      class BotApi
        include FlowChat::Instrumentation
        include FlowChat::GatewayAsyncSupport

        attr_reader :client, :context

        def initialize(app, config = nil)
          @app = app
          @config = config || FlowChat::Telegram::Configuration.from_credentials
          @client = FlowChat::Telegram::Client.new(@config)

          FlowChat.logger.info { "BotApi: Initialized Telegram Bot API gateway" }
        end

        def call(context)
          @context = context
          @controller = context.controller
          request = @controller.request

          FlowChat.logger.debug { "BotApi: Processing #{request.request_method rescue 'POST'} request" }

          # Handle POST webhooks only
          if request.post?
            return handle_webhook(context)
          end

          @controller.head :bad_request
        end

        # Platform-specific middleware configuration
        def self.configure_middleware_stack(builder, custom_middleware)
          FlowChat.logger.debug { "BotApi: Configuring Telegram middleware stack" }
          builder.use custom_middleware
          builder.use FlowChat::Telegram::Middleware::ChoiceMapper
        end

        private

        def handle_webhook(context)
          begin
            parse_request_body(@controller.request)
            FlowChat.logger.debug { "BotApi: Successfully parsed webhook request body" }
          rescue JSON::ParserError => e
            FlowChat.logger.error { "BotApi: Failed to parse webhook body: #{e.message}" }
            return @controller.head :bad_request
          end

          # Validate webhook signature (skip in background)
          unless in_background? || valid_webhook_signature?(@controller.request)
            FlowChat.logger.warn { "BotApi: Invalid webhook signature - rejecting request" }
            return @controller.head :unauthorized
          end

          # Process update
          if @body["message"]
            process_message(@body["message"], context)
          elsif @body["callback_query"]
            process_callback_query(@body["callback_query"], context)
          else
            FlowChat.logger.debug { "BotApi: No message or callback_query in update - returning OK" }
            return @controller.head :ok
          end

          # Routing: async or inline
          if should_enqueue_async?
            enqueue_async_job
            return @controller.head :ok
          end

          handle_message_inline(context, @controller)
          @controller.head :ok
        end

        def process_message(message, context)
          chat = message["chat"]
          from = message["from"]

          context["request.id"] = chat["id"].to_s
          context["request.user_id"] = from["id"].to_s
          context["request.user_name"] = [from["first_name"], from["last_name"]].compact.join(" ")
          context["request.username"] = from["username"]
          context["request.gateway"] = :telegram_bot_api
          context["request.platform"] = :telegram
          context["request.message_id"] = message["message_id"].to_s
          context["request.timestamp"] = Time.at(message["date"]).iso8601
          context["request.body"] = @body

          context["telegram.client"] = @client
          context["telegram.chat_type"] = chat["type"]

          extract_message_content!(message, context)

          if context.input.present?
            instrument(Events::MESSAGE_RECEIVED, {
              from: from["id"].to_s,
              message: context.input,
              message_type: detect_message_type(message),
              chat_type: chat["type"]
            })
          end
        end

        def process_callback_query(callback_query, context)
          from = callback_query["from"]
          message = callback_query["message"]
          chat = message["chat"]

          context["request.id"] = chat["id"].to_s
          context["request.user_id"] = from["id"].to_s
          context["request.user_name"] = [from["first_name"], from["last_name"]].compact.join(" ")
          context["request.username"] = from["username"]
          context["request.gateway"] = :telegram_bot_api
          context["request.platform"] = :telegram
          context["request.message_id"] = message["message_id"].to_s
          context["request.timestamp"] = Time.current.iso8601
          context["request.body"] = @body

          context["telegram.client"] = @client
          context["telegram.callback_query_id"] = callback_query["id"]
          context["telegram.original_message_id"] = message["message_id"]
          context["telegram.chat_type"] = chat["type"]

          # Input is the callback_data
          context.input = callback_query["data"]

          # Auto-answer callback query to remove loading indicator
          @client.answer_callback_query(callback_query["id"])

          instrument(Events::MESSAGE_RECEIVED, {
            from: from["id"].to_s,
            message: context.input,
            message_type: "callback_query"
          })
        end

        def extract_message_content!(message, context)
          if message["text"]
            context.input = message["text"]
          elsif message["location"]
            context["request.location"] = {
              "latitude" => message["location"]["latitude"],
              "longitude" => message["location"]["longitude"]
            }
            context.input = FlowChat::Input::LOCATION
          elsif message["photo"]
            # Photos come as array, take highest resolution (last)
            photo = message["photo"].last
            context["request.media"] = {
              type: :photo,
              file_id: photo["file_id"],
              file_unique_id: photo["file_unique_id"],
              width: photo["width"],
              height: photo["height"]
            }
            context.input = FlowChat::Input::MEDIA
          elsif message["video"]
            video = message["video"]
            context["request.media"] = {
              type: :video,
              file_id: video["file_id"],
              file_unique_id: video["file_unique_id"],
              width: video["width"],
              height: video["height"],
              duration: video["duration"],
              mime_type: video["mime_type"]
            }
            context.input = FlowChat::Input::MEDIA
          elsif message["audio"]
            audio = message["audio"]
            context["request.media"] = {
              type: :audio,
              file_id: audio["file_id"],
              file_unique_id: audio["file_unique_id"],
              duration: audio["duration"],
              mime_type: audio["mime_type"],
              title: audio["title"],
              performer: audio["performer"]
            }
            context.input = FlowChat::Input::MEDIA
          elsif message["document"]
            doc = message["document"]
            context["request.media"] = {
              type: :document,
              file_id: doc["file_id"],
              file_unique_id: doc["file_unique_id"],
              file_name: doc["file_name"],
              mime_type: doc["mime_type"]
            }
            context.input = FlowChat::Input::MEDIA
          elsif message["voice"]
            voice = message["voice"]
            context["request.media"] = {
              type: :voice,
              file_id: voice["file_id"],
              file_unique_id: voice["file_unique_id"],
              duration: voice["duration"],
              mime_type: voice["mime_type"]
            }
            context.input = FlowChat::Input::MEDIA
          elsif message["sticker"]
            sticker = message["sticker"]
            context["request.media"] = {
              type: :sticker,
              file_id: sticker["file_id"],
              file_unique_id: sticker["file_unique_id"],
              width: sticker["width"],
              height: sticker["height"],
              is_animated: sticker["is_animated"],
              is_video: sticker["is_video"],
              emoji: sticker["emoji"],
              set_name: sticker["set_name"]
            }
            context.input = FlowChat::Input::MEDIA
          elsif message["contact"]
            context["request.contact"] = {
              phone_number: message["contact"]["phone_number"],
              first_name: message["contact"]["first_name"],
              last_name: message["contact"]["last_name"],
              user_id: message["contact"]["user_id"]
            }
            context.input = FlowChat::Input::CONTACT
          else
            context.input = ""
          end
        end

        def detect_message_type(message)
          return "text" if message["text"]
          return "location" if message["location"]
          return "photo" if message["photo"]
          return "video" if message["video"]
          return "audio" if message["audio"]
          return "document" if message["document"]
          return "voice" if message["voice"]
          return "sticker" if message["sticker"]
          return "contact" if message["contact"]
          "unknown"
        end

        def valid_webhook_signature?(request)
          return true if @config.skip_signature_validation
          return true unless @config.secret_token

          provided_token = request.headers["X-Telegram-Bot-Api-Secret-Token"]
          return false unless provided_token

          secure_compare(@config.secret_token, provided_token.to_s)
        end

        def secure_compare(a, b)
          return false unless a.bytesize == b.bytesize
          l = a.unpack("C*")
          res = 0
          b.each_byte { |byte| res |= byte ^ l.shift }
          res == 0
        end

        def handle_message_inline(context, controller)
          response = @app.call(context)
          return unless response

          _type, prompt, choices, media = response
          @client.send_message(context["request.id"], prompt, choices: choices, media: media)

          instrument(Events::MESSAGE_SENT, {
            to: context["request.id"],
            message: prompt,
            gateway: :telegram_bot_api,
            platform: :telegram
          })
        end

        def parse_request_body(request)
          return @body if @body

          if request.body.nil?
            @body = {}
          else
            request.body.rewind if request.body.respond_to?(:rewind)
            @body = JSON.parse(request.body.read)
          end
        end
      end
    end
  end
end
