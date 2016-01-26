module Procrastinator
   class Task
      # TODO: attributes: fail_count

      # TODO: should take procs for #run, #fail, #success, #final_fail,

      attr_reader :run_at, :queue, :strategy

      def initialize(run_at: Time.now, queue:, strategy:)
         @run_at   = run_at
         @queue    = queue
         @strategy = strategy

         raise(BadStrategyError.new('given strategy does not support #run method')) unless strategy.respond_to? :run
      end
   end

   class BadStrategyError < StandardError
   end
end