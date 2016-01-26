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

            try_hook(:success)
         rescue StandardError
            if max_attempts.nil? || @attempts <= max_attempts
               try_hook(:fail)
            else
               try_hook(:final_fail)

               raise FinalFailError.new('Task failed too many times.')
            end
         end
      end

      private
      def try_hook(method)
         begin
            @strategy.send(method)
         rescue StandardError => e
            $stderr.puts "#{method.to_s.capitalize} hook error: #{e.message}"
         end
      end
   end

   class BadStrategyError < StandardError
   end

   class FinalFailError < StandardError
   end
end