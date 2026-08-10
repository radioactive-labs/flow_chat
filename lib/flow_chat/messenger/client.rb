require "net/http"
require "json"
require "uri"

module FlowChat
  module Messenger
    class Client
      include FlowChat::Instrumentation

      def initialize(config)
        @config = config
        FlowChat.logger.info { "Messenger::Client: Initialized for page_id: #{@config.page_id}" }
      end

      def send_message(recipient_id, prompt, choices: nil, media: nil)
        response = renderer_class.new(prompt, choices: choices, media: media).render
        type, content, options = response

        instrument(Events::MESSAGE_SENT, {
          to: recipient_id,
          message_type: type.to_s,
          content_length: content.to_s.length,
          platform: platform
        }) do
          deliver(recipient_id, type, content, options)
        end
      end

      def send_text(recipient_id, text)
        send_message(recipient_id, text)
      end

      # Uploads a file for reuse and returns the id Meta assigned it.
      def upload_media(url, type: :image)
        payload = {
          message: {
            attachment: {
              type: type.to_s,
              payload: {url: url, is_reusable: true}
            }
          }
        }

        result = post_json(@config.attachment_upload_url, payload)
        result && result["attachment_id"]
      end

      private

      def renderer_class
        FlowChat::Messenger::Renderer
      end

      def platform
        :messenger
      end

      def limits
        FlowChat::Config.messenger
      end

      # Anything over the platform's cap is rejected whole rather than trimmed by
      # Meta, so long text goes as several messages. Only the last result is
      # returned: it carries the id of the message the user ends up looking at.
      def deliver(recipient_id, type, content, options)
        case type
        when :text
          split_text(content).map { |chunk| post_message(recipient_id, {text: chunk}) }.last
        when :quick_replies
          chunks = split_text(content)
          # Quick replies belong on the final chunk, next to the question.
          chunks[0..-2].each { |chunk| post_message(recipient_id, {text: chunk}) }
          post_message(recipient_id, {text: chunks.last, quick_replies: options[:quick_replies]})
        when :carousel
          post_message(recipient_id, {text: content}) if content.present?
          post_message(recipient_id, {
            attachment: {
              type: "template",
              payload: {template_type: "generic", elements: options[:elements]}
            }
          })
        when :attachment
          attachment_payload = options[:url] ? {url: options[:url], is_reusable: true} : {attachment_id: options[:attachment_id]}
          post_message(recipient_id, {text: content}) if content.present?
          post_message(recipient_id, {
            attachment: {type: options[:type].to_s, payload: attachment_payload}
          })
        end
      end

      def post_message(recipient_id, message)
        payload = {recipient: {id: recipient_id}, message: message}
        payload[:messaging_type] = "RESPONSE" if messaging_type?

        post_json(@config.messages_url, payload)
      end

      # Messenger documents messaging_type as required on a send. Instagram's
      # reference does not mention it at all, so Instagram omits it rather than
      # sending a parameter Meta never documented for that surface.
      def messaging_type?
        true
      end

      # Splits on whitespace so a word is never cut in half. Measured with the
      # platform's own unit, which is bytes on Instagram and characters here.
      def split_text(text)
        limit = limits.max_text_length
        return [text.to_s] if measure(text.to_s) <= limit

        chunks = []
        current = ""

        text.to_s.split(/(\s+)/).each do |piece|
          if measure(current + piece) > limit && current.present?
            chunks << current.strip
            current = piece.lstrip
          else
            current += piece
          end
        end

        chunks << current.strip if current.strip.present?
        chunks
      end

      def measure(string)
        string.length
      end

      def post_json(url, payload)
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(uri)
        @config.api_headers.each { |key, value| request[key] = value }
        request.body = payload.to_json

        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          JSON.parse(response.body)
        else
          FlowChat.logger.error { "#{self.class.name}: API request failed - #{response.code}: #{response.body}" }
          report_api_error(
            "#{platform} API request failed",
            response_code: response.code,
            response_body: response.body
          )
          nil
        end
      rescue Net::OpenTimeout, Net::ReadTimeout => network_error
        FlowChat.logger.error { "#{self.class.name}: Network timeout: #{network_error.class.name}" }
        raise network_error
      end

      # FlowChat::Instrumentation only defines report_api_error at the module
      # level (FlowChat::Instrumentation.report_api_error), not as an instance
      # method, so it is not inherited through `include`. Every client that
      # wants the shorthand defines its own wrapper; this mirrors the one in
      # whatsapp/client.rb.
      def report_api_error(message, response_code: nil, response_body: nil, error: nil)
        FlowChat::Instrumentation.report_api_error(
          message,
          error: error,
          platform: platform,
          page_id: @config.page_id,
          response_code: response_code,
          response_body: response_body
        )
      end
    end
  end
end
