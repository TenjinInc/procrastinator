require 'yaml'

module Procrastinator
   class TaskWorker
      attr_reader :id, :run_at, :initial_run_at, :task, :attempts, :last_fail_at, :status

      def initialize(id: nil,
                     run_at:,
                     initial_run_at:,
                     attempts: 0,
                     timeout: nil,
                     max_attempts: nil,
                     last_fail_at: nil,
                     task:)
         @id             = id
         @run_at         = run_at
         @initial_run_at = initial_run_at
         @task           = YAML.load(task)
         @attempts       = attempts
         @max_attempts   = max_attempts
         @timeout        = timeout
         @last_fail_at   = last_fail_at

         raise(MalformedTaskError.new('given task does not support #run method')) unless @task.respond_to? :run
         raise(ArgumentError.new('timeout cannot be negative')) if timeout && timeout < 0
         raise(ArgumentError.new('initial_run_at cannot be nil')) if @initial_run_at.nil?
      end

      def work
         @attempts += 1

         begin
            Timeout::timeout(@timeout) do
               @task.run
            end

            try_hook(:success)
            @status = :success
               #TODO: @last_error = nil
         rescue StandardError => e
            @last_fail_at = Time.now.to_i

            if final_fail?
               try_hook(:final_fail, e)

               #TODO: @last_error = 'Task failed too many times: ' + e.backtrace
               @status = :final_fail
            else
               try_hook(:fail, e)
               @status = :fail

               #TODO: @last_error = 'Task failed: ' + e.backtrace
            end
         end
      end

      def final_fail?
         !@max_attempts.nil? && @attempts >= @max_attempts
      end

      def to_hash
         {id:             @id,
          run_at:         @run_at,
          initial_run_at: @initial_run_at,
          attempts:       @attempts,
          last_fail_at:   @last_fail_at,
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