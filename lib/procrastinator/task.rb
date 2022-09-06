# frozen_string_literal: true

module Procrastinator
   # Wraps a task handler and task metadata
   #
   # @author Robin Miller
   class Task
      extend Forwardable

      def_delegators :@metadata,
                     :id, :run_at, :initial_run_at, :expire_at,
                     :attempts, :last_fail_at, :last_error,
                     :data, :successful?, :to_h, :final_fail?,
                     :fail, :serialized_data, :queue, :reschedule, :add_attempt, :expired?, :reset, :clear_fails

      def_delegators :@handler,
                     :run

      def initialize(metadata, handler)
         @metadata = metadata
         @handler  = handler
      end

      def try_hook(method, *params)
         @handler.send(method, *params) if @handler.respond_to? method
      rescue StandardError => e
         warn "#{ method.to_s.capitalize } hook error: #{ e.message }"
      end

      def verify_expiry!
         raise TaskExpiredError, "task is over its expiry time of #{ @metadata.expire_at.iso8601 }" if expired?
      end

      def to_s
         "#{ @metadata.queue.name } [#{ serialized_data }]"
      end
   end
end
