module Procrastinator
   class Queue
      DEFAULT_TIMEOUT       = 3600 # in seconds; one hour total
      DEFAULT_MAX_ATTEMPTS  = 20
      DEFAULT_UPDATE_PERIOD = 10 # seconds
      DEFAULT_MAX_TASKS     = 10

      attr_reader :name, :task_class, :max_attempts, :timeout, :update_period, :max_tasks

      # Timeout is in seconds
      def initialize(name:,
                     task_class:,
                     max_attempts: DEFAULT_MAX_ATTEMPTS,
                     timeout: DEFAULT_TIMEOUT,
                     update_period: DEFAULT_UPDATE_PERIOD,
                     max_tasks: DEFAULT_MAX_TASKS)
         raise ArgumentError.new(':name may not be nil') unless name
         raise ArgumentError.new(':task_class may not be nil') unless task_class

         raise ArgumentError.new('Task class must be initializable') unless task_class.respond_to? :new

         @name          = name.to_s.strip.gsub(/[^A-Za-z0-9]+/, '_').to_sym
         @task_class    = task_class
         @max_attempts  = max_attempts
         @timeout       = timeout
         @update_period = update_period
         @max_tasks     = max_tasks
      end
   end
end