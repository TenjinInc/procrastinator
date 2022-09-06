# frozen_string_literal: true

module Procrastinator
   # TaskMetaData objects are State Patterns that record information about the work done on a particular task.
   #
   # It contains the specific information needed to run a task instance. Users define a task handler class, which
   # describes the "how" of a task and TaskMetaData represents the "what" and "when".
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

      attr_reader(*EXPECTED_DATA, :queue)

      def initialize(id: nil,
                     queue: nil,
                     run_at: nil,
                     initial_run_at: nil,
                     expire_at: nil,
                     attempts: 0,
                     last_error: nil,
                     last_fail_at: nil,
                     data: nil)
         @id             = id
         @queue          = queue || raise(ArgumentError, 'queue cannot be nil')
         @run_at         = get_time(run_at)
         @initial_run_at = get_time(initial_run_at) || @run_at
         @expire_at      = get_time(expire_at)
         @attempts       = (attempts || 0).to_i
         @last_error     = last_error
         @last_fail_at   = get_time(last_fail_at)
         @data           = data ? JSON.parse(data, symbolize_names: true) : nil
      end

      def add_attempt
         @attempts += 1
      end

      def fail(msg, final: false)
         @last_fail_at = Time.now
         @last_error   = msg
         @run_at       = nil if final
      end

      def final_fail?
         too_many_fails? || expired?
      end

      def expired?
         !@expire_at.nil? && @expire_at < Time.now
      end

      def too_many_fails?
         !@queue.max_attempts.nil? && @attempts >= @queue.max_attempts
      end

      def runnable?
         !@run_at.nil? && @run_at <= Time.now
      end

      def successful?
         raise 'you cannot check for success before running #work' if !expired? && @attempts <= 0

         !expired? && @last_error.nil? && @last_fail_at.nil?
      end

      # Updates the run and/or expiry time. If neither is provided, will reschedule based on the rescheduling
      # calculation algorithm.
      #
      # @param run_at - the new time to run this task
      # @param expire_at - the new time to expire this task
      def reschedule(run_at: nil, expire_at: nil)
         validate_run_at(run_at, expire_at)

         @expire_at = expire_at if expire_at

         if run_at
            @run_at = @initial_run_at = get_time(run_at)
            reset
         end

         return if run_at || expire_at

         # (30 + n_attempts^4) seconds is chosen to rapidly expand
         # but with the baseline of 30s to avoid hitting the disk too frequently.
         @run_at += 30 + (@attempts ** 4) unless @run_at.nil?
      end

      def to_h
         {id:             @id,
          queue:          @queue.name,
          run_at:         @run_at&.iso8601,
          initial_run_at: @initial_run_at&.iso8601,
          expire_at:      @expire_at&.iso8601,
          attempts:       @attempts,
          last_fail_at:   @last_fail_at&.iso8601,
          last_error:     @last_error,
          data:           serialized_data}
      end

      def serialized_data
         JSON.dump(@data)
      end

      def clear_fails
         @last_error   = nil
         @last_fail_at = nil
      end

      def reset
         @attempts = 0
         clear_fails
      end

      private

      def get_time(data)
         case data
         when NilClass
            nil
         when Numeric
            Time.at data
         when String
            Time.parse data
         when Time
            data
         else
            return data.to_time if data.respond_to? :to_time

            raise ArgumentError, "Unknown data type: #{ data.class } (#{ data })"
         end
      end

      def validate_run_at(run_at, expire_at)
         return unless run_at

         if expire_at && run_at > expire_at
            raise ArgumentError, "new run_at (#{ run_at }) is later than new expire_at (#{ expire_at })"
         end

         return unless @expire_at && run_at > @expire_at

         raise ArgumentError, "new run_at (#{ run_at }) is later than existing expire_at (#{ @expire_at })"
      end
   end
end
