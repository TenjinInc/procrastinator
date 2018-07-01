require 'simplecov'

SimpleCov.start

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'timecop'
require 'fakefs/safe'

require 'procrastinator'

def fake_persister(data)
   persister = double('persister')
   allow(persister).to receive(:update_task)
   allow(persister).to receive(:delete_task)
   allow(persister).to receive(:read_tasks).and_return(data)
   persister
end

module Procrastinator

   module Test
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