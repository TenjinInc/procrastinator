module Procrastinator
   class TaskQueue
      DEFAULT_TIMEOUT      = 3600 # seconds = one hour
      DEFAULT_MAX_ATTEMPTS = 20

      attr_reader :name, :timeout, :max_attempts

      # Timeout is in seconds
      def initialize(name:, max_attempts: DEFAULT_MAX_ATTEMPTS, timeout: DEFAULT_TIMEOUT)
         raise ArgumentError.new('Queue name may not be nil') unless name
         raise ArgumentError.new('Queue name must be a symbol') unless name

         @name         = name.to_s.gsub(/\s/, '_').to_sym
         @timeout      = timeout
         @max_attempts = max_attempts
      end
   end
end