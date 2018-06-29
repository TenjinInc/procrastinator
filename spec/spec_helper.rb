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
            class BadRun
               def run

               end
            end

            class BadSuccess
               def run(context, logger)

               end

               def success

               end
            end

            class BadFail
               def run(context, logger)

               end

               def fail

               end
            end

            class BadFinalFail
               def run(context, logger)

               end

               def final_fail

               end
            end
         end

         class AllHooks
            def initialize(data = nil)

            end

            def run(context, logger)

            end

            def success(context, logger, result)

            end

            def fail(context, logger, error)

            end

            def final_fail(context, logger, error)

            end
         end

         class KeywordInit
            def initialize(test_data_one:, test_data_two:)

            end

            def run(context, logger)

            end
         end

         class RunOnly
            def run(context, logger)

            end
         end

         class Fail
            def run(context, logger)
               raise('derp')
            end

            def fail(context, logger, error)

            end
         end
      end
   end
end