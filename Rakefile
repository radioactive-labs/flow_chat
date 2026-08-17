require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"

# Load custom rake tasks
Dir.glob("lib/tasks/**/*.rake").each { |r| load r }

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  # test/performance holds benchmarks, which assert against wall-clock timings and
  # so fail on a loaded machine for reasons that have nothing to do with the code
  # under test. A suite that cries wolf is a suite people stop reading, so they
  # run under `rake benchmark` instead of here.
  t.test_files = FileList["test/**/*_test.rb"].exclude("test/performance/**/*_test.rb")
end

desc "Run the performance benchmarks (timing-sensitive, not part of rake test)"
Rake::TestTask.new(:benchmark) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/performance/**/*_test.rb"]
end

task default: %i[test standard]
