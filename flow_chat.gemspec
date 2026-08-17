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
  # Matches the versions CI actually exercises. The previous ">= 2.3.0" was
  # three Rubies out of date and promised a floor nothing here could honour:
  # activesupport 8 requires Ruby 3.2, so a 2.x user hit an unexplained
  # resolution failure rather than a clear statement of what this gem needs.
  spec.required_ruby_version = Gem::Requirement.new(">= 3.0")

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"

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

  # Deliberately unbounded above, and RubyGems' warning about that is
  # overridden knowingly rather than overlooked.
  #
  # A "< N" cap does not protect this gem from the next major - it decides
  # where the breakage surfaces. Capping blocks every downstream application on
  # the day that major ships, until this gem cuts a release, which is a cost
  # paid by everyone for a break that may never come.
  #
  # Leaving it open moves the risk from install time to runtime, and the CI job
  # against rails main is what pays for that: an incompatible change is found
  # while it is still unreleased, rather than in a bug report the week it lands.
  # If that job is ever removed, these bounds should be revisited.
  #
  # No floor is needed beyond ">= 6" either. Bundler resolves an activesupport
  # that suits the running Ruby, so a Ruby 3.0 application lands on Rails 7.x
  # without this gem having to say so.
  spec.add_dependency "activesupport", ">= 6"
  spec.add_dependency "actionpack", ">= 6"
  spec.add_dependency "zeitwerk"
  spec.add_dependency "phonelib"
  spec.add_dependency "ibsciss-middleware", "~> 0.4.2"
  spec.add_dependency "intercom", "~> 4.2"
  spec.add_dependency "reverse_markdown", "~> 3.0"
  spec.add_dependency "kramdown", "~> 2.4"
end
