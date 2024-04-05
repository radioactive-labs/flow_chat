module FlowChat
  module Ussd
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
        raise ArgumentError, "screen has been presented" if navigation_stack.include?(key)

        navigation_stack << key
        return session.get(key) if session.get(key).present?

        prompt = FlowChat::Ussd::Prompt.new input
        @input = nil # input is being submitted to prompt so we clear it

        value = yield prompt
        session.set(key, value)
        value
      end

      def say(msg)
        raise FlowChat::Interrupt::Terminate.new(msg)
      end
    end
  end
end
