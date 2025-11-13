require "active_job"
require "ostruct"

module FlowChat
  # Base class for background flow processing jobs
  # Users inherit from this and implement execute(controller)
  class AsyncJob < (defined?(ApplicationJob) ? ApplicationJob : ActiveJob::Base)
    def perform(request_context:)
      FlowChat.logger.debug { "AsyncJob: Starting background job" }

      # Create BackgroundController from serialized request
      controller = BackgroundController.new(request_context)

      # User implements execute and calls processor.run themselves
      execute(controller)

      FlowChat.logger.debug { "AsyncJob: Background job completed successfully" }
    end

    # Abstract method - user must implement
    # User builds processor AND calls processor.run themselves
    def execute(controller)
      raise NotImplementedError, "Subclasses must implement #execute(controller)"
    end
  end

  # Duck-type controller for background jobs
  # Provides render/head no-ops and request interface
  class BackgroundController
    attr_reader :request, :response

    def initialize(request_data)
      FlowChat.logger.debug { "BackgroundController: Initializing with request data" }
      @request = BackgroundRequest.new(request_data)
      @response = nil
    end

    # Delegate params to request (mimics Rails controller behavior)
    def params
      request.params
    end

    def render(options)
      FlowChat.logger.debug { "BackgroundController: render called (no-op): #{options.inspect}" }
      @response = options
      nil  # No-op in background
    end

    def head(status)
      FlowChat.logger.debug { "BackgroundController: head called (no-op): #{status}" }
      @response = {status: status}
      nil  # No-op in background
    end

    def is_a?(klass)
      return true if klass == FlowChat::BackgroundController
      super
    end

    def kind_of?(klass)
      return true if klass == FlowChat::BackgroundController
      super
    end
  end

  # Request object for background jobs
  # Reconstructed from serialized webhook request data
  class BackgroundRequest
    attr_reader :params, :method, :headers, :host, :path

    def initialize(request_data)
      @params = (request_data[:params] || {}).with_indifferent_access
      @method = request_data[:method] || "POST"
      @headers = OpenStruct.new(request_data[:headers] || {})
      @host = request_data[:host]
      @path = request_data[:path]

      FlowChat.logger.debug { "BackgroundRequest: Initialized with method=#{@method}, params keys=#{@params.keys.inspect}" }
    end

    def post?
      method.upcase == "POST"
    end

    def get?
      method.upcase == "GET"
    end

    def body
      # Background jobs don't have request body
      nil
    end

    def cookies
      # Background jobs don't have cookies
      {}
    end
  end
end
