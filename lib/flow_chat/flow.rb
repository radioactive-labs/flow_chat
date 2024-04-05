module FlowChat
  class Flow
    attr_reader :app

    def initialize(app)
      @app = app
    end
  end
end
