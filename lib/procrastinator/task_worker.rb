require 'yaml'
require 'ostruct'

module Procrastinator
   class TaskWorker
      extend Forwardable

      attr_reader :id, :task
      def_delegators :@timing_data, :run_at, :initial_run_at, :expire_at
      def_delegators :@failure_data, :attempts, :last_fail_at, :last_error

      def initialize(id: nil,
                     run_at: nil,
                     initial_run_at: nil,
                     expire_at: nil,
                     attempts: 0,
                     timeout: nil,
                     max_attempts: nil,
                     last_fail_at: nil,
                     last_error: nil,
                     task:)
         @id = id

         @timing_data = OpenStruct.new(run_at:         run_at.nil? ? nil : run_at.to_i,
                                       initial_run_at: initial_run_at.to_i,
                                       expire_at:      expire_at.nil? ? nil : expire_at.to_i,
                                       timeout:        timeout)

         @failure_data = OpenStruct.new(attempts:     attempts || 0,
                                        max_attempts: max_attempts,
                                        last_fail_at: last_fail_at,
                                        last_error:   last_error)

         @task = YAML.load(task)

         raise(MalformedTaskError.new('given task does not support #run method')) unless @task.respond_to? :run
         raise(ArgumentError.new('timeout cannot be negative')) if timeout && timeout < 0
      end

      def work(logger: Logger.new(StringIO.new), context: nil)
         @failure_data.attempts += 1

         begin
            raise(TaskExpiredError.new("task is over its expiry time of #{@timing_data.expire_at}")) if expired?

            result = Timeout::timeout(@timing_data.timeout) do
               @task.run(context, logger)
            end

            try_hook(:success, context, logger, result)

            logger.debug("Task completed: #{YAML.dump(@task)}")

            @failure_data.last_error   = nil
            @failure_data.last_fail_at = nil
         rescue StandardError => e
            @failure_data.last_fail_at = Time.now.to_i

            if too_many_fails? || expired?
               try_hook(:final_fail, context, logger, e)

               @timing_data.run_at      = nil
               @failure_data.last_error = "#{expired? ? 'Task expired' : 'Task failed too many times'}: #{e.backtrace.join("\n")}"

               logger.debug("Task failed permanently: #{YAML.dump(@task)}")
            else
               try_hook(:fail, context, logger, e)

               @failure_data.last_error = %Q[Task failed: #{e.message}\n#{e.backtrace.join("\n")}]
               logger.debug("Task failed: #{YAML.dump(@task)}")

               reschedule
            end
         end
      end

      def successful?
         if !expired? && @failure_data.attempts <= 0
            raise(RuntimeError, 'you cannot check for success before running #work')
         end

         @failure_data.last_error.nil? && @failure_data.last_fail_at.nil?
      end

      def too_many_fails?
         !@failure_data.max_attempts.nil? && @failure_data.attempts >= @failure_data.max_attempts
      end

      def expired?
         !@timing_data.expire_at.nil? && Time.now.to_i > @timing_data.expire_at
      end

      def task_hash
         {id:             @id,
          run_at:         @timing_data.run_at,
          initial_run_at: @timing_data.initial_run_at,
          expire_at:      @timing_data.expire_at,
          attempts:       @failure_data.attempts,
          last_fail_at:   @failure_data.last_fail_at,
          last_error:     @failure_data.last_error,
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

      def reschedule
         # (30 + n_attempts^4) seconds is chosen to rapidly expand
         # but with the baseline of 30s to avoid hitting the disk too frequently.
         @timing_data.run_at += 30 + (@failure_data.attempts ** 4)
      end
   end

   class TaskExpiredError < StandardError
   end

   class MalformedTaskError < StandardError
   end
end