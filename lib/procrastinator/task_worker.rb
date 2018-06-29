require 'yaml'
require 'ostruct'
require 'timeout'

module Procrastinator
   class TaskWorker
      extend Forwardable

      def_delegators :@task,
                     :id, :run_at, :initial_run_at, :expire_at,
                     :attempts, :last_fail_at, :last_error,
                     :data,
                     :to_h, :successful?

      def initialize(task:, queue:)
         @queue = queue

         @task         = task
         handler_class = queue.task_class
         @task_handler = @task.init_handler(handler_class)

         unless @task_handler.respond_to? :run
            raise(MalformedTaskError.new("task #{@task_handler.class} does not support #run method"))
         end
      end

      def work(logger: Logger.new(StringIO.new), context: nil)
         @task.add_attempt

         begin
            @task.verify_expiry

            result = Timeout::timeout(@queue.timeout) do
               @task_handler.run(context, logger)
            end

            logger.debug("Task completed: #{@task_handler.class} [#{@task.serialized_data}]")

            @task.clear_fails

            try_hook(:success, context, logger, result)
         rescue StandardError => e
            if @task.final_fail?(@queue)
               trace = e.backtrace.join("\n")
               msg   = "#{@task.expired? ? 'Task expired' : 'Task failed too many times'}: #{trace}"

               @task.fail(msg, final: true)

               logger.debug("Task failed permanently: #{YAML.dump(@task_handler)}")

               try_hook(:final_fail, context, logger, e)
            else
               @task.fail(%[Task failed: #{e.message}\n#{e.backtrace.join("\n")}])
               logger.debug("Task failed: #{@queue.name} with #{@task.serialized_data}")

               @task.reschedule

               try_hook(:fail, context, logger, e)
            end
         end
      end

      private

      def try_hook(method, *params)
         begin
            @task_handler.send(method, *params) if @task_handler.respond_to? method
         rescue StandardError => e
            $stderr.puts "#{method.to_s.capitalize} hook error: #{e.message}"
         end
      end
   end

   class MalformedTaskError < StandardError
   end
end