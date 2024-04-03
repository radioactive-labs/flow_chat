require "zeitwerk"
require "active_support"

loader = Zeitwerk::Loader.for_gem
loader.enable_reloading if defined?(Rails.env) && Rails.env.development?
loader.setup

module UssdEngine
  def self.root
    Pathname.new __dir__
  end
end

loader.eager_load
