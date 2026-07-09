require "bundler/gem_tasks"
require "rake/testtask"

# Load custom rake tasks
Dir.glob("lib/tasks/**/*.rake").each { |r| load r }

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test
