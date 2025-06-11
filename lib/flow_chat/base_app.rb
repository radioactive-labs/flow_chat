module FlowChat
  class BaseApp
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

      user_input = prepare_user_input
      prompt = FlowChat::Prompt.new user_input
      @input = nil # input is being submitted to prompt so we clear it

      value = yield prompt
      session.set(key, value)
      value
    end

    def go_back
      return false if navigation_stack.empty?
      
      @context.input = nil
      current_screen = navigation_stack.last
      session.delete(current_screen)
      
      # Restart the flow from the beginning
      raise FlowChat::Interrupt::RestartFlow.new
    end

    def say(msg, media: nil)
      raise FlowChat::Interrupt::Terminate.new(msg, media: media)
    end

    def phone_number
      context["request.msisdn"]
    end

    def message_id
      context["request.message_id"]
    end

    def timestamp
      context["request.timestamp"]
    end

    def contact_name
      nil
    end

    def location
      nil
    end

    def media
      nil
    end

    protected

    # Platform-specific methods to be overridden
    def prepare_user_input
      input
    end
  end
end 