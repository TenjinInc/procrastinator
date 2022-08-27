# frozen_string_literal: true

module Procrastinator
   # A Queue defines how a certain type task will be processed.
   #
   # @author Robin Miller
   #
   # @!attribute [r] :name
   #    @return [Symbol] The queue's identifier symbol
   # @!attribute [r] :task_class
   #    @return [Class] Class that defines the work to be done for jobs in this queue.
   # @!attribute [r] :timeout
   #    @return [Object] Duration (seconds) after which tasks in this queue should fail for taking too long.
   # @!attribute [r] :max_attempts
   #    @return [Object] Maximum number of attempts for tasks in this queue.
   # @!attribute [r] :update_period
   #    @return [Pathname] Delay (seconds) between reloads of tasks from the task store.
   class Queue
      extend Forwardable

      DEFAULT_TIMEOUT       = 3600 # in seconds; one hour total
      DEFAULT_MAX_ATTEMPTS  = 20
      DEFAULT_UPDATE_PERIOD = 10 # seconds

      attr_reader :name, :task_class, :max_attempts, :timeout, :update_period, :task_store

      alias store task_store
      alias storage task_store

      def_delegators :@task_store, :read, :create, :update, :delete

      # Timeout is in seconds
      def initialize(name:,
                     task_class:,
                     max_attempts: DEFAULT_MAX_ATTEMPTS,
                     timeout: DEFAULT_TIMEOUT,
                     update_period: DEFAULT_UPDATE_PERIOD,
                     store: TaskStore::SimpleCommaStore.new)
         raise ArgumentError, ':name cannot be nil' unless name

         raise ArgumentError, ':task_class cannot be nil' unless task_class
         raise ArgumentError, 'Task class must be initializable' unless task_class.respond_to? :new

         validate_task_store(store)

         raise ArgumentError, ':timeout cannot be negative' if timeout&.negative?

         @name          = name.to_s.strip.gsub(/[^A-Za-z0-9]+/, '_').to_sym
         @task_class    = task_class
         @task_store    = store
         @max_attempts  = max_attempts
         @timeout       = timeout
         @update_period = update_period
         freeze
      end

      private

      def validate_task_store(store)
         raise ArgumentError, ':store cannot be nil' if store.nil?

         [:read, :create, :update, :delete].each do |method|
            unless store.respond_to? method
               raise MalformedTaskStoreError, "task store #{ store.class } must respond to ##{ method }"
            end
         end
      end
   end

   class MalformedTaskStoreError < RuntimeError
   end
end
