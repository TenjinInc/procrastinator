# frozen_string_literal: true

module Procrastinator
   # A Scheduler object provides the API for client applications to manage delayed tasks.
   #
   # Use #delay to schedule new tasks, #reschedule to alter existing tasks, and #cancel to remove unwanted tasks.
   #
   # @author Robin Miller
   class Scheduler
      def initialize(config)
         @config = config
      end

      # Records a new task to be executed at the given time.
      #
      # @param queue_name [Symbol] the symbol identifier for the queue to add a new task on
      # @param run_at [Time, Integer] Optional time when this task should be executed. Defaults to the current time.
      # @param data [Hash, Array, String, Integer] Optional simple data object to be provided to the task on execution.
      # @param expire_at [Time, Integer] Optional time when the task should be abandoned
      def delay(queue_name = nil, data: nil, run_at: Time.now, expire_at: nil)
         raise ArgumentError, <<~ERR unless queue_name.nil? || queue_name.is_a?(Symbol)
            must provide a queue name as the first argument. Received: #{ queue_name }
         ERR

         queue = @config.queue(name: queue_name)

         queue.create(run_at: run_at, expire_at: expire_at, data: data)
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
         queue = @config.queue(name: queue)

         tasks = queue.read(identifier.merge(queue: queue.name.to_s))

         raise "no task matches search: #{ identifier }" if tasks.empty?
         raise "multiple tasks match search: #{ identifier }" if tasks.size > 1

         queue.delete(tasks.first[:id])
      end

      # Spawns a new worker thread for each queue defined in the config
      #
      # @param queue_names [Array<String,Symbol>] Names of specific queues to act upon.
      #                                           Omit or leave empty to act on all queues.
      def work(*queue_names)
         workers = filter_queues(queue_names).collect do |queue|
            QueueWorker.new(queue: queue, config: @config)
         end

         WorkProxy.new(workers, @config)
      end

      # Provides a more natural syntax for rescheduling tasks
      #
      # @see Scheduler#reschedule
      class UpdateProxy
         def initialize(queue, identifier:)
            @queue      = queue
            @identifier = identifier
         end

         def to(run_at: nil, expire_at: nil)
            task = @queue.fetch_task(@identifier)

            raise ArgumentError, 'you must provide at least :run_at or :expire_at' if run_at.nil? && expire_at.nil?

            task.reschedule(expire_at: expire_at) if expire_at
            task.reschedule(run_at: run_at) if run_at

            new_data = task.to_h
            new_data.delete(:queue)
            new_data.delete(:data)
            @queue.update(new_data.delete(:id), new_data)
         end

         alias at to
      end

      # Provides a more natural chained syntax for kicking off the queue working process
      #
      # @see Scheduler#work
      class WorkProxy
         PID_EXT          = '.pid'
         DEFAULT_PID_DIR  = Pathname.new('pid/').freeze
         DEFAULT_PID_FILE = Pathname.new("procrastinator#{ PID_EXT }").freeze
         PROG_NAME        = 'Procrastinator'

         # 15 chars is linux limit
         MAX_PROC_LEN = 15

         def initialize(workers, config)
            @workers = workers
            @config  = config
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
            open_log
            shutdown_on_interrupt

            @threads = spawn_threads

            @threads.each do |thread|
               thread.join(timeout)
            end
         rescue StandardError => e
            thread_crash(e)
         ensure
            @logger&.info 'Halting worker threads...'
            shutdown!
            @logger&.info 'Threads halted.'
         end

         # Consumes the current process and turns it into a background daemon. A log will be started in the log directory
         # defined in the configuration block.
         #
         # @param name [String] The process name to request from the OS.
         #                      Not guaranteed to be set, depending on OS support.
         # @param pid_path [Pathname|File|String] Path to where the process ID file is to be kept.
         #                                        Assumed to be a directory unless ends with '.pid '.
         def daemonized!(name: nil, pid_path: nil, log_path: nil, &block)
            spawn_daemon(name, pid_path)

            yield if block

            threaded

            @logger.info "Procrastinator running. Process ID: #{ Process.pid }"
         end

         private

         def spawn_threads
            @logger.info 'Starting worker threads...'

            @workers.collect do |worker|
               @logger.debug "Spawning: #{ worker.name }"
               Thread.new(worker) do |w|
                  Thread.current.abort_on_exception = true
                  Thread.current.thread_variable_set(:name, w.name)

                  begin
                     worker.work!
                  ensure
                     worker.halt
                  end
               end
            end
         end

         # "You, search from the spastic dentistry department down through disembowelment. You, cover children's dance
         #  recitals through holiday weekend IKEA. Go."
         def spawn_daemon(name, pid_path)
            # double fork to guarantee no terminal can be attached.
            exit if fork
            Process.setsid
            exit if fork
            Dir.chdir '/' # allows process to continue even if the pwd of its running terminal disappears (eg deleted)

            open_log

            @logger.info "Starting #{ PROG_NAME } daemon..."

            rename_process(name)

            manage_pid(pid_path)
         end

         def open_log
            return if @logger

            log_path = @config.log_dir / "#{ PROG_NAME.downcase }.log"
            log_path.dirname.mkpath

            @logger = Logger.new(log_path.to_s, # || $stderr
                                 progname:  PROG_NAME.downcase,
                                 level:     @config.log_level,
                                 formatter: Config::DEFAULT_LOG_FORMATTER)
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
               @logger.info "Procrastinator (pid #{ Process.pid }) halted."
            end
         end

         def rename_process(name)
            return if name.nil?

            if name.size > MAX_PROC_LEN
               @logger.warn "process name is longer than max length (#{ MAX_PROC_LEN }). Trimming to fit."
               name = name[0, MAX_PROC_LEN]
            end

            if system('pidof', name)
               @logger.warn "a process is already named '#{ name }'. Consider the 'name:' argument to distinguish."
            end

            Process.setproctitle(name)
         end

         def shutdown_on_interrupt
            Signal.trap('INT') do
               warn "\n" # just to separate the shutdown log item
               shutdown!
            end
         end

         def shutdown!
            (@threads || []).select(&:alive?).each(&:kill)
         end

         def thread_crash(error)
            crashed_threads = (@threads || []).select { |t| t.status.nil? }.collect do |thread|
               "Crashed thread: #{ thread.thread_variable_get(:name) }"
            end

            @logger.fatal <<~MSG
               Crash detected in queue worker thread.
                  #{ crashed_threads.join("\n") }
                  #{ error.message }
                  #{ error.backtrace.join("\n\t") }"
            MSG
         end
      end

      private

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
