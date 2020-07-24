# frozen_string_literal: true

module Procrastinator
   # A Scheduler object provides the API for client applications to manage delayed tasks.
   #
   # Use #delay to schedule new tasks, #reschedule to alter existing tasks, and #cancel to remove unwanted tasks.
   #
   # @author Robin Miller
   class Scheduler
      extend Forwardable

      def_delegators :@queue_manager, :act, :spawn_workers

      def initialize(config)
         @config        = config
         @queue_manager = QueueManager.new(config)
      end

      # Records a new task to be executed at the given time.
      #
      # @param queue [Symbol] the symbol identifier for the queue to add a new task on
      # @param run_at [Time, Integer] Optional time when this task should be executed. Defaults to the current time.
      # @param data [Hash, Array] Optional simple data object to be provided to the task upon execution.
      # @param expire_at [Time, Integer] Optional time when the task should be abandoned
      def delay(queue = nil, data: nil, run_at: Time.now.to_i, expire_at: nil)
         verify_queue_arg!(queue)

         queue = @config.queue.name if @config.single_queue?

         verify_queue_data!(queue, data)

         loader.create(queue:          queue.to_s,
                       run_at:         run_at.to_i,
                       initial_run_at: run_at.to_i,
                       expire_at:      expire_at.nil? ? nil : expire_at.to_i,
                       data:           YAML.dump(data))
      end

      # Alters an existing task to run at a new time, expire at a new time, or both.
      #
      # Call #to on the result and pass in the new :run_at and/or :expire_at.
      #
      # Example:
      #
      # scheduler.reschedule(:alerts, data: {user_id: 5}).to(run_at: Time.now, expire_at: Time.now + 10)
      #
      # The identifier can include any data field stored in the task loader. Often this is the information in :data.
      #
      # @param queue [Symbol] the symbol identifier for the queue to add a new task on
      # @param identifier [Hash] Some identifying information to find the appropriate task.
      #
      # @see TaskMetaData
      def reschedule(queue, identifier)
         UpdateProxy.new(@config, identifier: identifier.merge(queue: queue.to_s))
      end

      # Removes an existing task, as located by the givne identifying information.
      #
      # The identifier can include any data field stored in the task loader. Often this is the information in :data.
      #
      # @param queue [Symbol] the symbol identifier for the queue to add a new task on
      # @param identifier [Hash] Some identifying information to find the appropriate task.
      #
      # @see TaskMetaData
      def cancel(queue, identifier)
         tasks = loader.read(identifier.merge(queue: queue.to_s))

         raise "no task matches search: #{ identifier }" if tasks.empty?
         raise "multiple tasks match search: #{ identifier }" if tasks.size > 1

         loader.delete(tasks.first[:id])
      end

      # Provides a more natural syntax for rescheduling tasks
      #
      # @see Scheduler#reschedule
      class UpdateProxy
         def initialize(config, identifier:)
            identifier[:data] = YAML.dump(identifier[:data]) if identifier[:data]

            @config     = config
            @identifier = identifier
         end

         def to(run_at: nil, expire_at: nil)
            task = fetch_task(@identifier)

            verify_time_provided(run_at, expire_at)
            validate_run_at(run_at, task[:expire_at], expire_at)

            new_data = {
                  attempts:      0,
                  last_error:    nil,
                  last_error_at: nil
            }

            new_data = new_data.merge(run_at: run_at.to_i, initial_run_at: run_at.to_i) if run_at
            new_data = new_data.merge(expire_at: expire_at.to_i) if expire_at

            @config.loader.update(task[:id], new_data)
         end

         alias at to

         private

         def verify_time_provided(run_at, expire_at)
            raise ArgumentError, 'you must provide at least :run_at or :expire_at' if run_at.nil? && expire_at.nil?
         end

         def validate_run_at(run_at, saved_expire_at, expire_at)
            return unless run_at

            after_new_expire = expire_at && run_at.to_i > expire_at.to_i

            raise "given run_at (#{ run_at }) is later than given expire_at (#{ expire_at })" if after_new_expire

            after_old_expire = saved_expire_at && run_at.to_i > saved_expire_at

            raise "given run_at (#{ run_at }) is later than saved expire_at (#{ saved_expire_at })" if after_old_expire
         end

         def fetch_task(identifier)
            tasks = @config.loader.read(identifier)

            raise "no task found matching #{ identifier }" if tasks.nil? || tasks.empty?
            raise "too many (#{ tasks.size }) tasks match #{ identifier }. Found: #{ tasks }" if tasks.size > 1

            tasks.first
         end
      end

      private

      # Scheduler must always get the loader indirectly. If it saves the loader to an instance variable,
      # then that might hold a stale object reference. Better to fetch each time.
      def loader
         @config.loader
      end

      def verify_queue_arg!(queue_name)
         raise ArgumentError, <<~ERR if !queue_name.nil? && !queue_name.is_a?(Symbol)
            must provide a queue name as the first argument. Received: #{ queue_name }
         ERR

         raise ArgumentError, <<~ERR if queue_name.nil? && !@config.single_queue?
            queue must be specified when more than one is registered. Defined queues are: #{ @config.queues_string }
         ERR
      end

      def verify_queue_data!(queue_name, data)
         queue = @config.queue(name: queue_name)

         unless queue
            queue_list = @config.queues_string
            raise ArgumentError, "there is no :#{ queue_name } queue registered. Defined queues are: #{ queue_list }"
         end

         if data.nil?
            if queue.task_class.method_defined?(:data=)
               raise ArgumentError, "task #{ queue.task_class } expects to receive :data. Provide :data to #delay."
            end
         elsif !queue.task_class.method_defined?(:data=)
            raise ArgumentError, <<~ERROR
               task #{ queue.task_class } does not import :data. Add this in your class definition:
                     task_attr :data
            ERROR
         end
      end
   end
end
