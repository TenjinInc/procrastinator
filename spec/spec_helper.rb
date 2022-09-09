# frozen_string_literal: true

require 'simplecov'

SimpleCov.start

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'rspec'
require 'timecop'
require 'pp' # needed to fix a conflict with FakeFS
require 'fakefs/safe'
require 'fakefs/spec_helpers'

require 'procrastinator'

RSpec.configure do |config|
   config.include FakeFS::SpecHelpers
end

RSpec::Matchers.define :include_log_line do |level, msg|
   match do |file_name|
      actual_lines = file_name.readlines(chomp: true)
      actual_lines.any? do |line|
         line.include?(level) && line.include?(msg)
      end
   end
end

module Procrastinator
   module Test
      class Persister
         def read(_attributes)
         end

         def create(_data)
         end

         def update(_identifier, _data)
         end

         def delete(_identifier)
         end
      end

      module Task
         class AllHooks
            attr_accessor :container, :logger, :scheduler

            def run
            end

            def success(_result)
            end

            def fail(_error)
            end

            def final_fail(_error)
            end
         end

         class Fail
            attr_accessor :logger, :container, :scheduler

            def run
               raise('asplode')
            end

            def fail(error)
            end
         end

         class LogData
            attr_accessor :logger, :container, :scheduler, :data

            def run
               logger.info "Ran with data: #{ data }"
            end
         end
      end
   end
end

def fake_persister(data = [])
   persister = Procrastinator::Test::Persister.new
   allow(persister).to receive(:read).and_return(data)
   persister
end
