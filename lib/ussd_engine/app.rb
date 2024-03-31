module UssdEngine
  class App
    attr_reader :session, :input

    def initialize(context)
      @session = context["session"]
      @input = context["request.input"]
    end

    def screen(key)
      raise ArgumentError, "a block is expected" unless block_given?

      return session.get(key) if session.get(key).present?

      prompt = UssdEngine::Prompt.new input
      @input = nil # input is being submitted to prompt so we clear it

      value = yield prompt
      session.set(key, value)
      value
    end
  end
end
