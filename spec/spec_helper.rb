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
         module MissingParam
            class ArgRun
               def run(_params)
               end
            end

            class NoArgSuccess
               def run
               end

               def success
               end
            end

            class MultiArgSuccess
               def run
               end

               def success(_arg1, _arg2)
               end
            end

            class NoArgFail
               def run
               end

               def fail
               end
            end

            class MultiArgFail
               def run
               end

               def fail(_arg1, _arg2)
               end
            end

            class NoArgFinalFail
               def run
               end

               def final_fail
               end
            end

            class MultiArgFinalFail
               def run
               end

               def final_fail(_arg1, _arg2)
               end
            end
         end

         class AllHooks
            def run
            end

            def success(_result)
            end

            def fail(_error)
            end

            def final_fail(_error)
            end
         end

         class ExpectingTask
            extend Procrastinator::Task

            def run
            end
         end

         class RunOnly
            def run
            end
         end

         class Fail
            def run
               raise('derp')
            end

            def fail(error)
            end
         end
      end
   end
end

def fake_persister(data)
   persister = Procrastinator::Test::Persister.new
   allow(persister).to receive(:read).and_return(data)
   persister
end
