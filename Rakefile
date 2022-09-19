# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'yard'

RSpec::Core::RakeTask.new(:spec)

task default: :spec

YARD::Rake::YardocTask.new do |t|
   t.files = %w[lib/**/*.rb]
   # t.options       = %w[--some-option]
   t.stats_options = ['--list-undoc']
end
