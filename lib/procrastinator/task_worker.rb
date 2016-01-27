module Procrastinator
   class TaskWorker
      attr_reader :run_at, :queue, :task, :attempts

      def initialize(run_at: Time.now, queue:, task:)
         @run_at   = run_at
         @queue    = queue
         @task     = task
         @attempts = 0

         raise(MalformedTaskError.new('given task does not support #run method')) unless task.respond_to? :run
      end

      def work(max_attempts: nil)
         @attempts += 1

         begin
            Timeout::timeout(@queue.timeout) do
               @task.run
            end

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
            @task.send(method) if @task.respond_to? method
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