module FlowChat
  class Context
    def initialize
      @data = {}.with_indifferent_access
    end

    def [](key)
      @data[key]
    end

    def []=(key, value)
      @data[key] = value
    end

    def input = @data["request.input"]

    def session = @data["session"]

    def controller = @data["controller"]

    # def request = controller.request

    def flow = @data["flow.class"]
  end
end
