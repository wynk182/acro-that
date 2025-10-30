# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

desc "Run RuboCop"
task :rubocop do
  sh "bundle exec rubocop"
end

desc "Run RuboCop with auto-correct"
task "rubocop:fix" do
  sh "bundle exec rubocop --auto-correct"
end

task default: :spec
