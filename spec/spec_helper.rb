require 'simplecov'

SimpleCov.start

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'timecop'
require 'fakefs/safe'

require 'procrastinator'

# leave result+pid nil for parent thread, give int for child pid
def stub_fork(receiver, result_pid = nil)
   allow(receiver).to receive(:fork) do |&block|
      block.call
      result_pid
   end
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