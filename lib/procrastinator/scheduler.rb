# frozen_string_literal: true

require 'stringio'

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

      # Removes an existing task, as located by the given identifying information.
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
         queue_names = @config.queues if queue_names.empty?

         workers = queue_names.collect do |queue_name|
            QueueWorker.new(queue: queue_name, config: @config)
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

      # Serial work style
      #
      # @see WorkProxy
      module SerialWorking
         # Work off the given number of tasks for each queue and return
         # @param steps [integer] The number of tasks to complete.
         def serially(steps: 1)
            steps.times do
               workers.each(&:work_one)
            end
         end
      end

      # Threaded work style
      #
      # @see WorkProxy
      module ThreadedWorking
         PROG_NAME = 'Procrastinator'

         # Work off jobs per queue, each in its own thread.
         #
         # @param timeout Maximum number of seconds to run for. If nil, will run indefinitely.
         def threaded(timeout: nil)
            open_log
            shutdown_on_interrupt

            begin
               @threads = spawn_threads

               @logger.info "Procrastinator running. Process ID: #{ Process.pid }"
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
         end

         private

         def spawn_threads
            @logger.info "Starting workers for queues: #{ @workers.collect(&:name).join(', ') }"

            @workers.collect do |worker|
               @logger.debug "Spawning thread: #{ worker.name }"
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

         def shutdown_on_interrupt
            Signal.trap('INT') do
               warn "\n" # just to separate the shutdown log item
               shutdown!
            end
         end

         def shutdown!
            (@threads || []).select(&:alive?).each(&:kill)
         end

         def open_log(quiet: false)
            return if @logger

            log_devs = []

            log_devs << StringIO.new if quiet && !@config.log_level
            log_devs << $stderr unless quiet
            log_devs << log_path.open('a') if @config.log_level

            multi      = MultiIO.new(*log_devs)
            multi.sync = true

            @logger = Logger.new(multi,
                                 progname:  PROG_NAME.downcase,
                                 level:     @config.log_level || Logger::INFO,
                                 formatter: Config::DEFAULT_LOG_FORMATTER)
         end

         def log_path
            path = @config.log_dir / "#{ PROG_NAME.downcase }.log"
            path.dirname.mkpath
            # FileUtils.touch(log_path)
            path
         end

         # IO Multiplexer that forwards calls to a list of IO streams.
         class MultiIO
            def initialize(*stream)
               @streams = stream
            end

            (IO.methods << :path << :sync=).uniq.each do |method_name|
               define_method(method_name) do |*args|
                  able_streams(method_name).collect do |stream|
                     stream.send(method_name, *args)
                  end.last # forces consistent return result type for callers (but may lose some info)
               end
            end

            private

            def able_streams(method_name)
               @streams.select { |stream| stream.respond_to?(method_name) }
            end
         end
      end

      # Daemonized work style
      #
      # @see WorkProxy
      module DaemonWorking
         PID_EXT         = '.pid'
         DEFAULT_PID_DIR = Pathname.new('/var/run/').freeze

         # 15 chars is linux limit
         MAX_PROC_LEN = 15

         # Consumes the current process and turns it into a background daemon and proceed as #threaded.
         # Additional logging is recorded in the directory specified by the Procrastinator.setup configuration.
         #
         # If pid_path ends with extension '.pid', the basename will be requested as process title (depending on OS
         # support). An extensionless path is assumed to be a directory and a default filename (and proctitle) is used.
         #
         # @param pid_path [Pathname, File, String, nil] Path to where the process ID file is to be kept.
         def daemonized!(pid_path = nil)
            spawn_daemon(pid_path)

            threaded
         end

         # Normalizes the given pid path, including conversion to absolute path and defaults.
         #
         # @param pid_path [Pathname, File, String, nil] path to normalize
         def self.normalize_pid(pid_path)
            normalized = Pathname.new(pid_path || DEFAULT_PID_DIR)
            normalized /= "#{ PROG_NAME.downcase }#{ PID_EXT }" unless normalized.extname == PID_EXT

            normalized.expand_path
         end

         # Stops the procrastinator process denoted by the provided pid file
         def self.halt!(pid_path)
            pid_path = normalize_pid pid_path

            Process.kill('TERM', pid_path.read.to_i)
         end

         def self.running?(pid_path)
            pid = normalize_pid(pid_path).read.to_i

            # this raises Errno::ESRCH when no process found, therefore if found we should exit
            Process.getpgid pid

            true
         rescue Errno::ESRCH
            false
         end

         private

         def spawn_daemon(pid_path)
            pid_path = DaemonWorking.normalize_pid pid_path

            open_log quiet: true
            @logger.info "Starting #{ PROG_NAME } daemon..."

            print_debug_context

            # "You, search from the spastic dentistry department down through disembowelment.
            #  You, cover children's dance recitals through holiday weekend IKEA. Go."
            Process.daemon

            manage_pid pid_path
            rename_process pid_path
         rescue StandardError => e
            @logger&.fatal ([e.message] + e.backtrace).join("\n")
            raise e
         end

         def manage_pid(pid_path)
            ensure_unique(pid_path)

            @logger.debug "Managing pid at path: #{ pid_path }"
            pid_path.dirname.mkpath
            pid_path.write Process.pid.to_s

            at_exit do
               if pid_path.exist?
                  @logger.debug "Cleaning up pid file #{ pid_path }"
                  pid_path.delete
               end
               @logger.info "Procrastinator (pid #{ Process.pid }) halted."
            end
         end

         def ensure_unique(pid_path)
            return unless pid_path.exist?

            @logger.debug "Checking pid file #{ pid_path }"

            if DaemonWorking.running? pid_path
               hint = 'Either terminate that process or remove the pid file (if coincidental).'
               msg  = "Another process (pid #{ pid_path.read }) already exists for #{ pid_path }. #{ hint }"
               @logger.fatal msg
               raise ProcessExistsError, msg
            else
               @logger.warn "Replacing old pid file of defunct process (pid #{ pid_path.read }) at #{ pid_path }."
            end
         end

         def print_debug_context
            @logger.debug "Ruby Path: #{ ENV.fetch 'RUBY_ROOT' }"
            @logger.debug "Bundler Path: #{ ENV.fetch 'BUNDLE_BIN_PATH' }"
            # LOGNAME is the posix standard and is set by cron, so probably reliable.
            @logger.debug "Runtime User: #{ ENV.fetch('LOGNAME') || ENV.fetch('USERNAME') }"
         end

         def rename_process(pid_path)
            name = pid_path.basename(PID_EXT).to_s

            if name.size > MAX_PROC_LEN
               @logger.warn "Process name is longer than max length (#{ MAX_PROC_LEN }). Trimming to fit."
               name = name[0, MAX_PROC_LEN]
            end

            if system('pidof', name, out: File::NULL)
               @logger.warn "Another process is already named '#{ name }'. Consider the 'name:' keyword to distinguish."
            end

            @logger.debug "Renaming process to: #{ name }"
            Process.setproctitle name
         end

         include ThreadedWorking
      end

      # DSL grammar object to enable chaining #work with the three work modes.
      #
      # @see Scheduler#work
      class WorkProxy
         include SerialWorking
         include ThreadedWorking
         include DaemonWorking

         attr_reader :workers

         def initialize(workers, config)
            @workers = workers
            @config  = config
         end
      end
   end

   class ProcessExistsError < RuntimeError
   end
end
