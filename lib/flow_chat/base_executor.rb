module FlowChat
  class BaseExecutor
    def initialize(app)
      @app = app
      FlowChat.logger.debug { "#{log_prefix}: Initialized #{platform_name} executor middleware" }
    end

    def call(context)
      flow_class = context.flow
      action = context["flow.action"]
      session_id = context["session.id"]

      FlowChat.logger.info { "#{log_prefix}: Executing flow #{flow_class.name}##{action} for session #{session_id}" }

      platform_app = build_platform_app(context)
      FlowChat.logger.debug { "#{log_prefix}: #{platform_name} app built for flow execution" }

      flow = flow_class.new platform_app
      FlowChat.logger.debug { "#{log_prefix}: Flow instance created, invoking #{action} method" }

      flow.send action
      FlowChat.logger.warn { "#{log_prefix}: Flow execution failed to interact with user for #{flow_class.name}##{action}" }
      raise FlowChat::Interrupt::Terminate, "Unexpected end of flow."
    rescue FlowChat::Interrupt::RestartFlow => e
      FlowChat.logger.info { "#{log_prefix}: Flow restart requested - Session: #{session_id}, restarting #{action}" }
      retry
    rescue FlowChat::Interrupt::Prompt => e
      FlowChat.logger.info { "#{log_prefix}: Flow prompted user - Session: #{session_id}, Prompt: '#{e.prompt&.truncate(100)}'" }
      FlowChat.logger.debug { "#{log_prefix}: Prompt details - Choices: #{e.choices&.size || 0}, Has media: #{!e.media.nil?}" }
      [:prompt, e.prompt, e.choices, e.media]
    rescue FlowChat::Interrupt::Terminate => e
      FlowChat.logger.info { "#{log_prefix}: Flow terminated - Session: #{session_id}, Message: '#{e.prompt&.truncate(100)}'" }
      FlowChat.logger.debug { "#{log_prefix}: Destroying session #{session_id}" }
      context.session.destroy
      [:terminate, e.prompt, nil, e.media]
    rescue => error
      FlowChat.logger.error { "#{log_prefix}: Flow execution failed - #{flow_class.name}##{action}, Session: #{session_id}, Error: #{error.class.name}: #{error.message}" }
      FlowChat.logger.debug { "#{log_prefix}: Stack trace: #{error.backtrace.join("\n")}" }
      raise
    end

    protected

    # Subclasses must implement these methods
    def platform_name
      raise NotImplementedError, "Subclasses must implement platform_name"
    end

    def log_prefix
      raise NotImplementedError, "Subclasses must implement log_prefix"
    end

    def build_platform_app(context)
      raise NotImplementedError, "Subclasses must implement build_platform_app"
    end
  end
end 