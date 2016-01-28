module Procrastinator
   class TaskWorker
      attr_reader :run_at, :task, :attempts, :last_fail_at, :status

      def initialize(run_at: Time.now, attempts: 0, timeout: nil, max_attempts: nil, task:)
         raise(MalformedTaskError.new('given task does not support #run method')) unless task.respond_to? :run
         raise(ArgumentError.new('Timeout cannot be negative')) if timeout && timeout < 0

         @run_at       = run_at
         @task         = task
         @attempts     = attempts
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
            @status = :success
         rescue StandardError => e
            @last_fail_at = Time.now.to_i

            if final_fail?
               try_hook(:final_fail, e)

               #TODO: @last_error_reason = 'Task failed too many times.')
               @status = :final_fail
            else
               try_hook(:fail, e)
               @status = :fail
            end
         end
      end

      def final_fail?
         !@max_attempts.nil? && @attempts >= @max_attempts
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
end