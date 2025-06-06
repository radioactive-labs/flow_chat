module FlowChat
  class Context
    include FlowChat::Instrumentation

    def initialize
      @data = {}.with_indifferent_access

      # Use instrumentation for context creation
      self.class.instrument(Events::CONTEXT_CREATED, {
        gateway: @data["request.gateway"]
      })
    end

    def [](key)
      value = @data[key]
      FlowChat.logger.debug { "Context: Getting '#{key}' = #{value.inspect}" } if key != "session.store" # Avoid logging session store object
      value
    end

    def []=(key, value)
      FlowChat.logger.debug { "Context: Setting '#{key}' = #{value.inspect}" } if key != "session.store" && key != "controller" # Avoid logging large objects
      @data[key] = value
    end

    def input = @data["request.input"]

    def input=(value)
      FlowChat.logger.debug { "Context: Setting input = '#{value}'" }
      @data["request.input"] = value
    end

    def session = @data["session"]

    def session=(value)
      FlowChat.logger.debug { "Context: Setting session = #{value.class.name}" }
      @data["session"] = value
    end

    def controller = @data["controller"]

    # def request = controller.request

    def flow = @data["flow.class"]
  end
end
