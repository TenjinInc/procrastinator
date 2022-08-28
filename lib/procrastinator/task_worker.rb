# frozen_string_literal: true

require 'json'
require 'ostruct'
require 'timeout'
require 'forwardable'

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
                     :data, :successful?, :to_h

      attr_reader :task

      def initialize(metadata:, task:, logger: Logger.new(StringIO.new))
         @metadata = metadata
         @task     = task
         @logger   = logger
      end

      def work(timeout = nil)
         @metadata.add_attempt

         @metadata.verify_expiry!

         result = Timeout.timeout(timeout) do
            @task.run
         end

         @logger&.debug("Task completed: #{ @metadata.queue.name } [#{ @metadata.serialized_data }]")

         @metadata.clear_fails

         try_hook(:success, result)
      rescue StandardError => e
         if @metadata.final_fail?
            handle_final_failure(e)
         else
            handle_failure(e)
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
         @logger&.debug("Task failed: #{ @metadata.queue.name } with #{ @metadata.serialized_data }")

         @metadata.reschedule

         try_hook(:fail, error)
      end

      def handle_final_failure(error)
         trace = error.backtrace.join("\n")
         msg   = "#{ @metadata.expired? ? 'Task expired' : 'Task failed too many times' }: #{ trace }"

         @metadata.fail(msg, final: true)

         @logger&.debug("Task failed permanently: #{ JSON.dump(@task) }")

         try_hook(:final_fail, error)
      end
   end
end
