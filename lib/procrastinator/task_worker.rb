require 'yaml'
require 'ostruct'
require 'timeout'

module Procrastinator
   class TaskWorker
      extend Forwardable

      def_delegators :@task_data, :id, :run_at, :initial_run_at, :expire_at, :attempts, :last_fail_at, :last_error, :data

      def initialize(id: nil,
                     run_at: nil,
                     initial_run_at: nil,
                     expire_at: nil,
                     attempts: 0,
                     queue:,
                     last_fail_at: nil,
                     last_error: nil,
                     data: nil)
         @queue = queue

         @task_data      = OpenStruct.new(id:             id,
                                          run_at:         run_at.nil? ? nil : run_at.to_i,
                                          initial_run_at: initial_run_at.to_i,
                                          expire_at:      expire_at.nil? ? nil : expire_at.to_i,
                                          attempts:       attempts || 0,
                                          last_fail_at:   last_fail_at,
                                          last_error:     last_error,
                                          data:           nil)

         @task_data.data = YAML.load(data) if data

         @task = @task_data.data ? queue.task_class.new(@task_data.data) : queue.task_class.new

         raise(MalformedTaskError.new("task #{@task.class} does not support #run method")) unless @task.respond_to? :run
      end

      def work(logger: Logger.new(StringIO.new), context: nil)
         @task_data.attempts += 1

         begin
            raise(TaskExpiredError.new("task is over its expiry time of #{@task_data.expire_at}")) if expired?

            result = Timeout::timeout(@queue.timeout) do
               @task.run(context, logger)
            end

            try_hook(:success, context, logger, result)

            logger.debug("Task completed: #{@task.class} [#{@task_data.data}]")

            @task_data.last_error   = nil
            @task_data.last_fail_at = nil
         rescue StandardError => e
            @task_data.last_fail_at = Time.now.to_i

            if @queue.too_many_fails?(@task_data.attempts) || expired?
               try_hook(:final_fail, context, logger, e)

               @task_data.run_at     = nil
               @task_data.last_error = "#{expired? ? 'Task expired' : 'Task failed too many times'}: #{e.backtrace.join("\n")}"

               logger.debug("Task failed permanently: #{YAML.dump(@task)}")
            else
               try_hook(:fail, context, logger, e)

               @task_data.last_error = %Q[Task failed: #{e.message}\n#{e.backtrace.join("\n")}]
               logger.debug("Task failed: #{YAML.dump(@task)}")

               reschedule
            end
         end
      end

      def successful?
         if !expired? && @task_data.attempts <= 0
            raise(RuntimeError, 'you cannot check for success before running #work')
         end

         @task_data.last_error.nil? && @task_data.last_fail_at.nil?
      end

      def expired?
         !@task_data.expire_at.nil? && Time.now.to_i > @task_data.expire_at
      end

      def task_hash
         {id:             @task_data.id,
          run_at:         @task_data.run_at,
          initial_run_at: @task_data.initial_run_at,
          expire_at:      @task_data.expire_at,
          attempts:       @task_data.attempts,
          last_fail_at:   @task_data.last_fail_at,
          last_error:     @task_data.last_error,
          data:           YAML.dump(@task_data.data)}
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
         @task_data.run_at += 30 + (@task_data.attempts ** 4) unless @task_data.run_at.nil?
      end
   end

   class TaskExpiredError < StandardError
   end

   class MalformedTaskError < StandardError
   end
end