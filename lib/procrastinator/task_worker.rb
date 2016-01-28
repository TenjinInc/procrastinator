module Procrastinator
   class TaskWorker
      attr_reader :run_at, :task, :attempts, :last_fail_at

      def initialize(run_at: Time.now, timeout: nil, max_attempts: nil, task:)
         raise(MalformedTaskError.new('given task does not support #run method')) unless task.respond_to? :run
         raise(ArgumentError.new('Timeout cannot be negative')) if timeout && timeout < 0

         @run_at       = run_at
         @task         = task
         @attempts     = 0
         @max_attempts = max_attempts
         @timeout      = timeout
      end

      def work
         @attempts += 1

         begin
            Timeout::timeout(@timeout) do
               @task.run
            end

            try_hook(:success)
         rescue StandardError => e
            @last_fail_at = Time.now.to_i

            if @max_attempts.nil? || @attempts <= @max_attempts # TODO: refactor this out to #over_limit?
               try_hook(:fail, e)
            else
               try_hook(:final_fail, e)

               raise FinalFailError.new('Task failed too many times.') #TODO: remove this, just record error reason instead
            end
         end
      end

      private
      def try_hook(method, *params)
         begin
            @task.send(method, *params) if @task.respond_to? method
         rescue StandardError => e
            $stderr.puts "#{method.to_s.capitalize} hook error: #{e.message}"
         end
      end
   end

   class MalformedTaskError < StandardError
   end

   class FinalFailError < StandardError
   end
end