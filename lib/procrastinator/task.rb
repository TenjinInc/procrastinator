# frozen_string_literal: true

require 'forwardable'
require 'time'

module Procrastinator
   # Wraps a task handler and task metadata
   #
   # @author Robin Miller
   class Task
      extend Forwardable

      def_delegators :@metadata,
                     :id, :run_at, :initial_run_at, :expire_at,
                     :attempts, :last_fail_at, :last_error,
                     :data, :to_h, :serialized_data,
                     :queue, :reschedule

      def initialize(metadata, handler)
         @metadata = metadata
         @handler  = handler
      end

      # Executes the Task Handler's #run hook and records the attempt.
      #
      # If the #run hook completes successfully, the #success hook will also be executed, if defined.
      #
      # @raise [ExpiredError] when the task run_at is after the expired_at.
      # @raise [AttemptsExhaustedError] when the task has been attempted more times than allowed by the queue settings.
      def run
         raise ExpiredError, "task is over its expiry time of #{ @metadata.expire_at.iso8601 }" if @metadata.expired?

         @metadata.add_attempt
         result = Timeout.timeout(queue.timeout) do
            @handler.run
         end
         @metadata.clear_fails

         try_hook(:success, result)
      end

      alias call run

      # Records a failure in metadata and attempts to run the handler's #fail hook if present.
      #
      # @param error [StandardError] - the error that caused the failure
      def fail(error)
         hook = @metadata.failure(error)

         try_hook(hook, error)
         hook
      end

      # Attempts to run the given optional event hook on the handler, catching any resultant errors to prevent the whole
      # task from failing despite the actual work in #run completing.
      def try_hook(method, *params)
         @handler.send(method, *params) if @handler.respond_to? method
      rescue StandardError => e
         warn "#{ method.to_s.capitalize } hook error: #{ e.message }"
      end

      # Convert the task into a human-legible string.
      # @return [String] Including the queue name, id, and serialized data.
      def to_s
         "#{ @metadata.queue.name }##{ id } [#{ serialized_data }]"
      end

      # Raised when a Task's run_at is beyond its expire_at
      class ExpiredError < RuntimeError
      end

      # Raised when a Task's attempts has exceeded the max_attempts defined for its queue (if any).
      class AttemptsExhaustedError < RuntimeError
      end
   end
end
