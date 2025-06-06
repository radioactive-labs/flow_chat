require "zeitwerk"
require "active_support"
require "active_support/core_ext/time"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/filters"
require "active_support/core_ext/enumerable"

loader = Zeitwerk::Loader.for_gem
loader.enable_reloading if defined?(Rails.env) && Rails.env.development?
loader.setup

module FlowChat
  def self.root
    Pathname.new __dir__
  end
  
  def self.setup_instrumentation!
    require_relative "flow_chat/instrumentation/setup"
    FlowChat::Instrumentation::Setup.setup_instrumentation!
  end
  
  # Access to instrumentation
  def self.instrument(event_name, payload = {}, &block)
    FlowChat::Instrumentation.instrument(event_name, payload, &block)
  end
  
  def self.metrics
    FlowChat::Instrumentation::Setup.metrics_collector
  end
end

loader.eager_load

# Auto-setup instrumentation in Rails environments
if defined?(Rails)
  Rails.application.config.after_initialize do
    FlowChat.setup_instrumentation!
  end
end
