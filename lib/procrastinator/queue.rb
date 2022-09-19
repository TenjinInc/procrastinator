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

      # Default number of seconds to wait for a task to complete
      DEFAULT_TIMEOUT = 3600 # in seconds; one hour total

      # Default number of times to retry a task
      DEFAULT_MAX_ATTEMPTS = 20

      # Default amount of time between checks for new Tasks
      DEFAULT_UPDATE_PERIOD = 10 # seconds

      attr_reader :name, :max_attempts, :timeout, :update_period, :task_store, :task_class

      alias store task_store
      alias storage task_store

      def_delegators :@task_store, :read, :update, :delete

      # Timeout is in seconds
      def initialize(name:, task_class:,
                     max_attempts: DEFAULT_MAX_ATTEMPTS,
                     timeout: DEFAULT_TIMEOUT,
                     update_period: DEFAULT_UPDATE_PERIOD,
                     store: TaskStore::SimpleCommaStore.new)
         raise ArgumentError, ':name cannot be nil' unless name

         raise ArgumentError, ':task_class cannot be nil' unless task_class
         raise ArgumentError, 'Task class must be initializable' unless task_class.respond_to? :new

         raise ArgumentError, ':timeout cannot be negative' if timeout&.negative?

         @name          = name.to_s.strip.gsub(/[^A-Za-z0-9]+/, '_').to_sym
         @task_class    = task_class
         @task_store    = store
         @max_attempts  = max_attempts
         @timeout       = timeout
         @update_period = update_period

         validate!

         freeze
      end

      # Constructs the next available task on the queue.
      #
      # @param logger [Logger] logger to provide to the constructed task handler
      # @param container [Object, nil] container to provide to the constructed task handler
      # @param scheduler [Procrastinator::Scheduler, nil] the scheduler to provide to the constructed task handler
      # @return [LoggedTask, nil] A Task or nil if no task is found
      def next_task(logger: Logger.new(StringIO.new), container: nil, scheduler: nil)
         metadata = next_metas.find(&:runnable?)

         return nil unless metadata

         task = Task.new(metadata, task_handler(data:      metadata.data,
                                                container: container,
                                                logger:    logger,
                                                scheduler: scheduler))

         LoggedTask.new(task, logger: logger)
      end

      # Fetch a task matching the given identifier
      #
      # @param identifier [Hash] attributes to match
      def fetch_task(identifier)
         identifier[:data] = JSON.dump(identifier[:data]) if identifier[:data]

         tasks = read(**identifier)

         raise "no task found matching #{ identifier }" if tasks.nil? || tasks.empty?
         raise "too many (#{ tasks.size }) tasks match #{ identifier }. Found: #{ tasks }" if tasks.size > 1

         TaskMetaData.new(tasks.first.merge(queue: self))
      end

      # Creates a task on the queue, saved using the Task Store strategy.
      #
      # @param run_at [Time] Earliest time to attempt running the task
      # @param expire_at [Time, nil] Time after which the task will not be attempted
      # @param data [Hash, String, Numeric, nil] The data to save
      def create(run_at:, expire_at:, data:)
         if data.nil? && expects_data?
            raise ArgumentError, "task #{ @task_class } expects to receive :data. Provide :data to #delay."
         end

         unless data.nil? || expects_data?
            raise MalformedTaskError, <<~ERROR
               found unexpected :data argument. Either do not provide :data when scheduling a task,
               or add this in the #{ @task_class } class definition:
                     attr_accessor :data
            ERROR
         end

         # TODO: shorten to using slice once updated to Ruby 2.5+
         attrs = {queue: self, run_at: run_at, initial_run_at: run_at, expire_at: expire_at, data: JSON.dump(data)}

         create_data = TaskMetaData.new(**attrs).to_h
         create_data.delete(:id)
         create_data.delete(:attempts)
         create_data.delete(:last_fail_at)
         create_data.delete(:last_error)
         @task_store.create(**create_data)
      end

      # @return [Boolean] whether the task handler will accept data to be assigned via its :data attribute
      def expects_data?
         @task_class.method_defined?(:data=)
      end

      private

      def task_handler(data: nil, container: nil, logger: nil, scheduler: nil)
         handler           = @task_class.new
         handler.data      = data if handler.respond_to?(:data=)
         handler.container = container
         handler.logger    = logger
         handler.scheduler = scheduler
         handler
      end

      def next_metas
         tasks = read(queue: @name).reject { |t| t[:run_at].nil? }.collect do |t|
            t.to_h.delete_if { |key| !TaskMetaData::EXPECTED_DATA.include?(key) }.merge(queue: self)
         end

         sort_tasks(tasks.collect { |t| TaskMetaData.new(**t) })
      end

      def sort_tasks(tasks)
         # TODO: improve this
         # shuffling and re-sorting to avoid worst case O(n^2) when receiving already sorted data
         # on quicksort (which is default ruby sort). It is not unreasonable that the persister could return sorted
         # results
         # Ideally, we'd use a better algo than qsort for this, but this will do for now
         tasks.shuffle.sort_by(&:run_at)
      end

      # Internal queue validator
      module QueueValidation
         private

         def validate!
            verify_task_class!
            verify_task_store!
         end

         def verify_task_class!
            verify_run_method!
            verify_accessors!
            verify_hooks!
         end

         # The interface compliance is checked on init because it's one of those rare cases where you want to know early;
         # otherwise, you wouldn't know until task execution and that could be far in the future.
         # UX is important for devs, too.
         #    - R
         def verify_run_method!
            unless @task_class.method_defined? :run
               raise MalformedTaskError, "task #{ @task_class } does not support #run method"
            end

            return unless @task_class.instance_method(:run).arity.positive?

            raise MalformedTaskError, "task #{ @task_class } cannot require parameters to its #run method"
         end

         def verify_accessors!
            [:logger, :container, :scheduler].each do |method_name|
               next if @task_class.method_defined?(method_name) && @task_class.method_defined?("#{ method_name }=")

               raise MalformedTaskError, <<~ERR
                  Task handler is missing a #{ method_name } accessor. Add this to the #{ @task_class } class definition:
                     attr_accessor :logger, :container, :scheduler
               ERR
            end
         end

         def verify_hooks!
            expected_arity = 1

            [:success, :fail, :final_fail].each do |method_name|
               next unless @task_class.method_defined?(method_name)
               next if @task_class.instance_method(method_name).arity == expected_arity

               err = "task #{ @task_class } must accept #{ expected_arity } parameter to its ##{ method_name } method"

               raise MalformedTaskError, err
            end
         end

         def verify_task_store!
            raise ArgumentError, ':store cannot be nil' if @task_store.nil?

            [:read, :create, :update, :delete].each do |method|
               unless @task_store.respond_to? method
                  raise MalformedTaskStoreError, "task store #{ @task_store.class } must respond to ##{ method }"
               end
            end
         end
      end
      include QueueValidation
   end

   # Raised when a Task Handler does not conform to the expected API
   class MalformedTaskError < StandardError
   end

   # Raised when a Task Store strategy does not conform to the expected API
   class MalformedTaskStoreError < RuntimeError
   end
end
