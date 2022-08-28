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

      attr_reader :name, :max_attempts, :timeout, :update_period, :task_store

      alias store task_store
      alias storage task_store

      def_delegators :@task_store, :read, :update, :delete

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

         verify_task_class(task_class)
         verify_task_store(store)

         raise ArgumentError, ':timeout cannot be negative' if timeout&.negative?

         @name          = name.to_s.strip.gsub(/[^A-Za-z0-9]+/, '_').to_sym
         @task_class    = task_class
         @task_store    = store
         @max_attempts  = max_attempts
         @timeout       = timeout
         @update_period = update_period
         freeze
      end

      def task_handler(data: nil, container: nil, logger: nil, scheduler: nil)
         handler           = @task_class.new
         handler.data      = data if handler.respond_to?(:data=)
         handler.container = container if handler.respond_to?(:container=)
         handler.logger    = logger if handler.respond_to?(:logger=)
         handler.scheduler = scheduler if handler.respond_to?(:scheduler=)
         handler
      end

      def create(run_at:, initial_run_at:, expire_at:, data:)
         if data.nil? && expects_data?
            raise ArgumentError, "task #{ @task_class } expects to receive :data. Provide :data to #delay."
         end

         unless data.nil? || expects_data?
            raise MalformedTaskError, <<~ERROR
               task #{ @task_class } does not import :data. Add this in your class definition:
                     task_attr :data
            ERROR
         end

         @task_store.create(queue:          @name.to_s,
                            run_at:         run_at,
                            initial_run_at: initial_run_at,
                            expire_at:      expire_at,
                            data:           JSON.dump(data))
      end

      def expects_container?
         @task_class.method_defined?(:container=)
      end

      def expects_data?
         @task_class.method_defined?(:data=)
      end

      private

      def verify_task_class(task_class)
         unless task_class.method_defined? :run
            raise MalformedTaskError, "task #{ task_class } does not support #run method"
         end

         # It checks the interface compliance on init because it's one of those rare cases where you want to know early;
         # otherwise, you wouldn't know until task execution and that could be far in the future.
         # UX is important for devs, too.
         #    - R
         if task_class.method_defined?(:run) && task_class.instance_method(:run).arity.positive?
            err = "task #{ task_class } cannot require parameters to its #run method"

            raise MalformedTaskError, err
         end

         expected_arity = 1

         [:success, :fail, :final_fail].each do |method_name|
            next unless task_class.method_defined?(method_name)
            next if task_class.instance_method(method_name).arity == expected_arity

            err = "task #{ task_class } must accept #{ expected_arity } parameter to its ##{ method_name } method"

            raise MalformedTaskError, err
         end
      end

      def verify_task_store(store)
         raise ArgumentError, ':store cannot be nil' if store.nil?

         [:read, :create, :update, :delete].each do |method|
            unless store.respond_to? method
               raise MalformedTaskStoreError, "task store #{ store.class } must respond to ##{ method }"
            end
         end
      end
   end

   class MalformedTaskError < StandardError
   end

   class MalformedTaskStoreError < RuntimeError
   end
end
