module Procrastinator
   class TaskQueue
      DEFAULT_TIMEOUT      = 3600 # seconds = one hour
      DEFAULT_MAX_ATTEMPTS = 20

      attr_reader :name, :timeout, :max_attempts

      # Timeout is in seconds
      def initialize(name: '', max_attempts: DEFAULT_MAX_ATTEMPTS, timeout: DEFAULT_TIMEOUT)
         @name         = name
         @timeout      = timeout
         @max_attempts = max_attempts
      end
   end
end