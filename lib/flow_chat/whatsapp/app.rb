module FlowChat
  module Whatsapp
    class App
      attr_reader :session, :input, :context, :navigation_stack

      def initialize(context)
        @context = context
        @session = context.session
        @input = context.input
        @navigation_stack = []
      end

      def screen(key)
        raise ArgumentError, "a block is expected" unless block_given?
        raise ArgumentError, "screen has already been presented" if navigation_stack.include?(key)

        navigation_stack << key
        return session.get(key) if session.get(key).present?

        user_input = input
        if session.get("$started_at$").nil?
          session.set("$started_at$", Time.current.iso8601)
          user_input = nil
        end

        prompt = FlowChat::Prompt.new user_input
        @input = nil # input is being submitted to prompt so we clear it

        value = yield prompt
        session.set(key, value)
        value
      end

      def say(msg, media: nil)
        raise FlowChat::Interrupt::Terminate.new(msg, media: media)
      end

      # WhatsApp-specific data accessors (read-only)
      def contact_name
        context["request.contact_name"]
      end

      def message_id
        context["request.message_id"]
      end

      def timestamp
        context["request.timestamp"]
      end

      def location
        context["request.location"]
      end

      def media
        context["request.media"]
      end

      def phone_number
        context["request.msisdn"]
      end
    end
  end
end
