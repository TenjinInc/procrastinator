# frozen_string_literal: true

module Procrastinator
   # TaskMetaData objects are State Patterns that record information about the work done on a particular task.
   #
   # It contains the specific information needed to run a task instance. Users define a task class, which describes
   # the "how" of a task and TaskMetaData represents the "what" and "when".
   #
   # It contains task-specific data, timing information, and error records.
   #
   # All of its state is read-only.
   #
   # @author Robin Miller
   #
   # @!attribute [r] :id
   #    @return [Integer] the unique identifier for this task
   # @!attribute [r] :run_at
   #    @return [Integer] Linux epoch timestamp of when to attempt this task next
   # @!attribute [r] :initial_run_at
   #    @return [Integer] Linux epoch timestamp of the original value for run_at
   # @!attribute [r] :expire_at
   #    @return [Integer] Linux epoch timestamp of when to consider this task obsolete
   # @!attribute [r] :attempts
   #    @return [Integer] The number of times this task has been attempted
   # @!attribute [r] :last_error
   #    @return [String] The message and stack trace of the error encountered on the most recent failed attempt
   # @!attribute [r] :last_fail_at
   #    @return [Integer] Linux epoch timestamp of when the last_error was recorded
   # @!attribute [r] :data
   #    @return [String] App-provided JSON data
   class TaskMetaData
      # These are the attributes expected to be in the persistence mechanism
      EXPECTED_DATA = [:id, :run_at, :initial_run_at, :expire_at, :attempts, :last_error, :last_fail_at, :data].freeze

      attr_reader(*EXPECTED_DATA)

      def initialize(id: nil,
                     run_at: nil,
                     initial_run_at: nil,
                     expire_at: nil,
                     attempts: 0,
                     last_error: nil,
                     last_fail_at: nil,
                     data: nil)
         @id             = id
         @run_at         = run_at.nil? ? nil : run_at.to_i
         @initial_run_at = initial_run_at.to_i
         @expire_at      = expire_at.nil? ? nil : expire_at.to_i
         @attempts       = attempts || 0
         @last_error     = last_error
         @last_fail_at   = last_fail_at
         @data           = data ? JSON.parse(data, symbolize_names: true) : nil
      end

      def add_attempt
         @attempts += 1
      end

      def clear_fails
         @last_error   = nil
         @last_fail_at = nil
      end

      def fail(msg, final: false)
         @last_fail_at = Time.now.to_i
         @last_error   = msg
         @run_at       = nil if final
      end

      def final_fail?(queue)
         too_many_fails?(queue) || expired?
      end

      def expired?
         !@expire_at.nil? && Time.now.to_i > @expire_at
      end

      def too_many_fails?(queue)
         !queue.max_attempts.nil? && @attempts >= queue.max_attempts
      end

      def runnable?
         !(@run_at.nil? || Time.now.to_i < @run_at)
      end

      def successful?
         raise 'you cannot check for success before running #work' if !expired? && @attempts <= 0

         !expired? && @last_error.nil? && @last_fail_at.nil?
      end

      def reschedule
         # (30 + n_attempts^4) seconds is chosen to rapidly expand
         # but with the baseline of 30s to avoid hitting the disk too frequently.
         @run_at += 30 + (@attempts ** 4) unless @run_at.nil?
      end

      def serialized_data
         JSON.dump(@data)
      end

      def verify_expiry!
         raise TaskExpiredError, "task is over its expiry time of #{ @expire_at }" if expired?
      end

      def to_h
         {id:             @id,
          run_at:         @run_at,
          initial_run_at: @initial_run_at,
          expire_at:      @expire_at,
          attempts:       @attempts,
          last_fail_at:   @last_fail_at,
          last_error:     @last_error,
          data:           serialized_data}
      end
   end

   class TaskExpiredError < StandardError
   end
end
