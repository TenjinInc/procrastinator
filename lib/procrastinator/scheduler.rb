# frozen_string_literal: true

module Procrastinator
   # A Scheduler object provides the API for client applications to manage delayed tasks.
   #
   # Use #delay to schedule new tasks, #reschedule to alter existing tasks, and #cancel to remove unwanted tasks.
   #
   # @author Robin Miller
   class Scheduler
      extend Forwardable

      def initialize(config)
         @config = config
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

      # Spawns a new worker thread for each queue defined in the config
      #
      # @param queue_names [Array<String,Symbol>] Names of specific queues to act upon.
      #                                           Omit or leave empty to act on all queues.
      def work(*queue_names)
         workers = filter_queues(queue_names).collect do |queue|
            QueueWorker.new(queue: queue, config: @config)
         end

         WorkProxy.new(workers)
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

      # Provides a more natural chained syntax for kicking off the queue working process
      #
      # @see Scheduler#work
      class WorkProxy
         PID_EXT          = '.pid'
         DEFAULT_PID_DIR  = Pathname.new('pid/').freeze
         DEFAULT_PID_FILE = Pathname.new("procrastinator#{ PID_EXT }").freeze

         # 15 chars is linux limit
         MAX_PROC_LEN = 15

         def initialize(workers)
            @workers = workers
         end

         # Work off the given number of tasks for each queue and return
         # @param steps [integer] The number of tasks to complete.
         def serially(steps: 1)
            steps.times do
               @workers.each(&:work_one)
            end
         end

         # Work off jobs per queue, each in its own thread.
         def threaded(timeout: nil)
            threads = @workers.collect do |worker|
               Thread.new do
                  worker.work
               end
            end

            threads.each { |thread| thread.join(timeout) }
         end

         # Consumes the current process and turns it into a background daemon.
         #
         # @param name [String] The process name to request from the OS.
         #                      Not guaranteed to be set, depending on OS support.
         # @param pid_path [Pathname|File|String] Path to where the process ID file is to be kept.
         #                                        Assumed to be a directory unless ends with '.pid'.
         def daemonized!(name: nil, pid_path: nil, &block)
            spawn_daemon(pid_path, name)

            yield if block

            threaded

            warn("Procrastinator running. Process ID: #{ Process.pid }")
         end

         private

         # "And his name is ... Shawn?"
         def spawn_daemon(pid_path, name)
            # double fork to guarantee no terminal can be attached.
            exit if fork
            Process.setsid
            exit if fork
            Dir.chdir '/' # allows process to continue even if the pwd of its running terminal disappears (eg deleted)

            warn('Starting Procrastinator...')

            manage_pid(pid_path)

            rename_process(name)
         end

         def manage_pid(pid_path)
            pid_path = Pathname.new(pid_path || DEFAULT_PID_DIR)

            if pid_path.extname == PID_EXT
               pid_path.dirname.mkpath
            else
               pid_path.mkpath
               pid_path /= DEFAULT_PID_FILE
            end

            pid_path.write(Process.pid.to_s)

            at_exit do
               pid_path.delete if pid_path.exist?
               warn("Procrastinator (pid #{ Process.pid }) halted.")
            end
         end

         def rename_process(name)
            return if name.nil?

            warn "Warning: process name is longer than max length (#{ MAX_PROC_LEN }). Trimming to fit."
            name = name[0, MAX_PROC_LEN]

            warn "Warning: a process is already named \"#{ name }\". Consider the \"name:\" argument to distinguish."
            Process.setproctitle(name)
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

      # Find Queues that match the given queue names, or all queues if no names provided.
      # @param :queue_names [Array<String,Symbol>] List of queue names to match. If empty, will return all queues.
      def filter_queues(queue_names)
         queue_names ||= []

         @config.queues.select do |queue|
            queue_names.empty? || queue_names.include?(queue.name)
         end
      end
   end
end
