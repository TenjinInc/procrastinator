module Procrastinator
   class Task
      attr_reader :run_at, :queue, :strategy, :attempts

      def initialize(run_at: Time.now, queue:, strategy:)
         @run_at   = run_at
         @queue    = queue
         @strategy = strategy
         @attempts = 0

         raise(BadStrategyError.new('given strategy does not support #run method')) unless strategy.respond_to? :run
      end

      def perform(max_attempts: nil)
         @attempts += 1

         begin
            @strategy.run
         rescue StandardError
            if max_attempts.nil? || @attempts <= max_attempts
               @strategy.fail
            else
               @strategy.final_fail
               raise FinalFailError.new('Task failed too many times.')
            end
         else
            # the strategy #run completed happily
            begin
               @strategy.success
            rescue StandardError => e
               $stderr.puts "Success hook failed: #{e.message}"
            end
         end
      end
   end

   class BadStrategyError < StandardError
   end

   class FinalFailError < StandardError
   end
end