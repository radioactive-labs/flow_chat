require_relative "lib/flow_chat/version"

Gem::Specification.new do |spec|
  spec.name = "flow_chat"
  spec.version = FlowChat::VERSION
  spec.authors = ["Stefan Froelich"]
  spec.email = ["sfroelich01@gmail.com"]

  spec.summary = "Build conversational interfaces for USSD and WhatsApp with Rails"
  spec.description = <<~DESC
    FlowChat is a Rails framework for building sophisticated conversational interfaces across USSD and WhatsApp platforms. 
    Create interactive flows with menus, prompts, validation, media support, and session management. Features include 
    multi-tenancy, background job processing, built-in simulator for testing, and comprehensive middleware support.
  DESC
  spec.homepage = "https://github.com/radioactive-labs/flow_chat"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path("..", __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "zeitwerk"
  spec.add_dependency "activesupport", ">= 6"
  spec.add_dependency "actionpack", ">= 6"
  spec.add_dependency "phonelib"
  spec.add_dependency "ibsciss-middleware", "~> 0.4.2"
end
