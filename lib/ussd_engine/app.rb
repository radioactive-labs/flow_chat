module UssdEngine
  class App
    attr_reader :session, :input, :context, :navigation_stack

    def initialize(context)
      @context = context
      @session = context["session"]
      @input = context["request.input"]
      @navigation_stack = []
    end

    def screen(key)
      raise ArgumentError, "a block is expected" unless block_given?
      raise ArgumentError, "screen has been presented" if navigation_stack.include?(key)

      navigation_stack << key
      return session.get(key) if session.get(key).present?

      prompt = UssdEngine::Prompt.new input
      @input = nil # input is being submitted to prompt so we clear it

      value = yield prompt
      session.set(key, value)
      value
    end

    def terminate!(msg)
      raise UssdEngine::Processor::Terminate.new(msg)
    end
  end
end
