require 'yaml'

module Procrastinator
   class TaskWorker
      attr_reader :id, :run_at, :initial_run_at, :task, :attempts, :last_fail_at, :last_error

      def initialize(id: nil,
                     run_at: nil,
                     initial_run_at: nil,
                     attempts: 0,
                     timeout: nil,
                     max_attempts: nil,
                     last_fail_at: nil,
                     last_error: nil,
                     task:)
         @id             = id
         @run_at         = run_at
         @initial_run_at = initial_run_at
         @task           = YAML.load(task)
         @attempts       = attempts
         @max_attempts   = max_attempts
         @timeout        = timeout
         @last_fail_at   = last_fail_at
         @last_error     = last_error

         raise(MalformedTaskError.new('given task does not support #run method')) unless @task.respond_to? :run
         raise(ArgumentError.new('timeout cannot be negative')) if timeout && timeout < 0
      end

      def work
         @attempts += 1

         begin
            Timeout::timeout(@timeout) do
               @task.run
            end

            try_hook(:success)
            @last_error   = nil
            @last_fail_at = nil
         rescue StandardError => e
            @last_fail_at = Time.now.to_i

            if too_many_fails?
               try_hook(:final_fail, e)

               @run_at     = nil
               @last_error = 'Task failed too many times: ' + e.backtrace.join("\n")
            else
               try_hook(:fail, e)

               @last_error = 'Task failed: ' + e.backtrace.join("\n")
            end
         end
      end

      def successful?
         raise(RuntimeError, 'you cannot check for success before running #work') unless @attempts > 0

         @last_error.nil? && @last_fail_at.nil?
      end

      def too_many_fails?
         !@max_attempts.nil? && @attempts >= @max_attempts
      end

      def to_hash
         {id:             @id,
          run_at:         @run_at,
          initial_run_at: @initial_run_at,
          attempts:       @attempts,
          last_fail_at:   @last_fail_at,
          last_error:     @last_error,
          task:           YAML.dump(@task)}
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