require "active_support"

module UssdEngine
  def self.root
    Pathname.new __dir__
  end
end

# Setup Zeitwerk
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.enable_reloading if defined?(Rails.env) && Rails.env.development?
loader.setup
