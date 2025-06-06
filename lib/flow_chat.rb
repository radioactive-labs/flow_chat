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
end

loader.eager_load
