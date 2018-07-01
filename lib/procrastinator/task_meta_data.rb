module Procrastinator
   class TaskMetaData
      attr_reader(:id, :run_at, :initial_run_at, :expire_at, :attempts, :last_error, :last_fail_at, :data)

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
         @data           = data ? YAML.load(data) : nil
      end

      def init_task(queue)
         @data ? queue.task_class.new(@data) : queue.task_class.new
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
         if !expired? && @attempts <= 0
            raise(RuntimeError, 'you cannot check for success before running #work')
         end

         !expired? && @last_error.nil? && @last_fail_at.nil?
      end

      def reschedule
         # (30 + n_attempts^4) seconds is chosen to rapidly expand
         # but with the baseline of 30s to avoid hitting the disk too frequently.
         @run_at += 30 + (@attempts ** 4) unless @run_at.nil?
      end

      def serialized_data
         YAML.dump(@data)
      end

      def verify_expiry!
         raise(TaskExpiredError.new("task is over its expiry time of #{@expire_at}")) if expired?
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