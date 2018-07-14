# frozen_string_literal: true

require 'yaml'
require 'ostruct'
require 'timeout'

module Procrastinator
   class TaskWorker
      extend Forwardable

      def_delegators :@metadata,
                     :id, :run_at, :initial_run_at, :expire_at,
                     :attempts, :last_fail_at, :last_error,
                     :data,
                     :to_h, :successful?

      def initialize(metadata:,
                     queue:,
                     logger: Logger.new(StringIO.new),
                     context: nil,
                     scheduler: nil)
         @queue = queue

         @metadata       = metadata
         @task           = queue.task_class.new

         @task.data      = @metadata.data if @task.respond_to?(:data=)
         @task.context   = context if @task.respond_to?(:context=)
         @task.logger    = logger if @task.respond_to?(:logger=)
         @task.scheduler = scheduler if @task.respond_to?(:scheduler=)

         @logger  = logger
         @context = context

         raise MalformedTaskError, "task #{ @task.class } does not support #run method" unless @task.respond_to? :run
      end

      def work
         @metadata.add_attempt

         begin
            @metadata.verify_expiry!

            result = Timeout.timeout(@queue.timeout) do
               @task.run
            end

            @logger&.debug("Task completed: #{ @task.class } [#{ @metadata.serialized_data }]")

            @metadata.clear_fails

            try_hook(:success, result)
         rescue StandardError => error
            if @metadata.final_fail?(@queue)
               handle_final_failure(error)
            else
               handle_failure(error)
            end
         end
      end

      private

      def try_hook(method, *params)
         @task.send(method, *params) if @task.respond_to? method
      rescue StandardError => e
         warn "#{ method.to_s.capitalize } hook error: #{ e.message }"
      end

      def handle_failure(error)
         @metadata.fail(%[Task failed: #{ error.message }\n#{ error.backtrace.join("\n") }])
         @logger&.debug("Task failed: #{ @queue.name } with #{ @metadata.serialized_data }")

         @metadata.reschedule

         try_hook(:fail, error)
      end

      def handle_final_failure(error)
         trace = error.backtrace.join("\n")
         msg   = "#{ @metadata.expired? ? 'Task expired' : 'Task failed too many times' }: #{ trace }"

         @metadata.fail(msg, final: true)

         @logger&.debug("Task failed permanently: #{ YAML.dump(@task) }")

         try_hook(:final_fail, error)
      end
   end

   class MalformedTaskError < StandardError
   end
end
