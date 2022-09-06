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

      def_delegators :@task, :successful?, :id, :attempts, :to_h

      attr_reader :task

      def initialize(task, logger: Logger.new(StringIO.new))
         @task   = task
         @logger = logger
      end

      def work(timeout = nil)
         @task.add_attempt

         @task.verify_expiry!

         result = Timeout.timeout(timeout) do
            @task.run
         end

         @task.clear_fails

         @logger&.debug("Task completed: #{ @task }")

         @task.try_hook(:success, result)
      rescue StandardError => e
         if @task.final_fail?
            handle_final_failure(e)
         else
            handle_failure(e)
         end
      end

      private

      def handle_failure(error)
         @task.fail(%[Task failed: #{ error.message }\n#{ error.backtrace.join("\n") }])
         @logger&.debug("Task failed: #{ @task }")

         @task.reschedule

         @task.try_hook(:fail, error)
      end

      def handle_final_failure(error)
         trace = error.backtrace.join("\n")
         msg   = "#{ @task.expired? ? 'Task expired' : 'Task failed too many times' }: #{ trace }"

         @task.fail(msg, final: true)

         @logger&.debug("Task failed permanently: #{ @task }")

         @task.try_hook(:final_fail, error)
      end
   end
end
