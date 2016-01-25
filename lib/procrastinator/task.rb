module Procrastinator
   class Task
      # TODO: attributes: run_count, run_at [time or int], queue

      # TODO: should take blocks for #job, #fail, #success, #final_fail,

      attr_reader :run_at, :queue


      def initialize(run_at: Time.now, queue:)
         @run_at = run_at
         @queue  = queue
      end
   end
end