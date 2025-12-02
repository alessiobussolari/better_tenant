# frozen_string_literal: true

require "bundler/gem_tasks"

begin
  require "rspec/core/rake_task"
  RSpec::Core::RakeTask.new(:spec)
  task default: :spec
rescue LoadError
  # RSpec not available
end

begin
  require "rubocop/rake_task"
  RuboCop::RakeTask.new
rescue LoadError
  # RuboCop not available
end
