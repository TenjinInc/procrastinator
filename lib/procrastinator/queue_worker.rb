module Procrastinator
   class QueueWorker
      DEFAULT_TIMEOUT       = 3600 # seconds = one hour
      DEFAULT_MAX_ATTEMPTS  = 20
      DEFAULT_UPDATE_PERIOD = 10 # seconds
      DEFAULT_MAX_TASKS     = 10

      attr_reader :name, :timeout, :max_attempts, :update_period, :max_tasks

      # Timeout is in seconds
      def initialize(name:,
                     max_attempts: DEFAULT_MAX_ATTEMPTS,
                     timeout: DEFAULT_TIMEOUT,
                     update_period: DEFAULT_UPDATE_PERIOD,
                     max_tasks: DEFAULT_MAX_TASKS)
         raise ArgumentError.new('Queue name may not be nil') unless name
         raise ArgumentError.new('Queue name must be a symbol') unless name

         @name          = name.to_s.gsub(/\s/, '_').to_sym
         @timeout       = timeout
         @max_attempts  = max_attempts
         @update_period = update_period
         @max_tasks     = max_tasks
      end
   end
end