# frozen_string_literal: true

require 'yaml'
require 'ostruct'
require 'timeout'

module Procrastinator
   # Works on a given task by creating a new instance of the queue's task class and running the appropriate hooks.
   #
   # The behaviour outside of the actual user-defined task is guided by the provided metadata.
   #
   # @author Robin Miller
   #
   # @see TaskMetaData
   class TaskWorker
      extend Forwardable

      def_delegators :@metadata,
                     :id, :run_at, :initial_run_at, :expire_at,
                     :attempts, :last_fail_at, :last_error,
                     :data, :successful?

      def initialize(metadata:,
                     queue:,
                     logger: Logger.new(StringIO.new),
                     container: nil,
                     scheduler: nil)
         @queue = queue

         @metadata       = metadata
         @task           = queue.task_class.new

         @task.data      = @metadata.data if @task.respond_to?(:data=)
         @task.container = container if @task.respond_to?(:container=)
         @task.logger    = logger if @task.respond_to?(:logger=)
         @task.scheduler = scheduler if @task.respond_to?(:scheduler=)

         @logger    = logger
         @container = container

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
         rescue StandardError => e
            if @metadata.final_fail?(@queue)
               handle_final_failure(e)
            else
               handle_failure(e)
            end
         end
      end

      def to_h
         @metadata.to_h.merge(queue: @queue.name.to_sym)
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
