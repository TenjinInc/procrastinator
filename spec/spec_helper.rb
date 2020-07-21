require 'simplecov'

SimpleCov.start

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'rspec'
require 'timecop'
require 'pp' # needed to fix a conflict with FakeFS
require 'fakefs/safe'
require 'fakefs/spec_helpers'

require 'procrastinator'

module Procrastinator

   module Test
      class Persister
         def read(attributes)
         end

         def create(data)
         end

         def update(identifier, data)
         end

         def delete(identifier)
         end
      end


      module Task
         module MissingParam
            class ArgRun
               def run(params)
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

               def success(a, b)
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

               def fail(a, b)
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

               def final_fail(a, b)
               end
            end
         end

         class AllHooks
            def run
            end

            def success(result)
            end

            def fail(error)
            end

            def final_fail(error)
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
