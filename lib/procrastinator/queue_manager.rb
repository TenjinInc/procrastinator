# frozen_string_literal: true

module Procrastinator
   # Spawns and manages work queue subprocesses.
   #
   # This is where all of the multi-process logic should be kept to.
   #
   # @author Robin Miller
   #
   # @!attribute [r] :workers
   #    @return [Hash] Maps the constructed QueueWorkers to their process ID.
   class QueueManager
      attr_reader :workers

      def initialize(config)
         @workers = {}
         @config  = config
         @logger  = start_log
      end

      # Shuts down any remaining old queue workers and spawns a new one for each queue defined in the config
      #
      # @return [Scheduler] a scheduler object that can be used to interact with the queues
      def spawn_workers
         scheduler = Scheduler.new(@config, self)

         kill_old_workers

         if ENV['PROCRASTINATOR_STOP']
            @logger.warn('Cannot spawn queue workers because environment variable PROCRASTINATOR_STOP is set')
         else
            @config.queues.each do |queue|
               spawn_worker(queue, scheduler: scheduler)
            end
         end

         scheduler
      end

      # Produces a new QueueWorker for the given queue.
      #
      # If Test Mode is disabled in the config, then it will also fork a new independent process for that worker
      # to work in.
      #
      # @param queue [Queue] the queue to build a worker for
      # @param scheduler [Scheduler] an optional scheduler instance to pass to the worker
      def spawn_worker(queue, scheduler: nil)
         worker = QueueWorker.new(queue:     queue,
                                  config:    @config,
                                  scheduler: scheduler)
         if @config.test_mode?
            @workers[worker] = Process.pid
         else
            check_for_name(worker.long_name)

            pid = fork

            if pid
               # === PARENT PROCESS ===
               Process.detach(pid)
               @workers[worker] = pid
            else
               deamonize(worker.long_name)

               worker.work
               shutdown_worker
            end
         end
      end

      def act(*queue_names)
         unless @config.test_mode?
            raise <<~ERR
               Procrastinator.act called outside Test Mode.
               Either use Procrastinator.spawn_workers or call #enable_test_mode in Procrastinator.setup.
            ERR
         end

         workers = @workers.keys

         if queue_names.empty?
            workers.each(&:act)
         else
            queue_names.each do |name|
               workers.find { |worker| worker.name == name }.act
            end
         end
      end

      private

      def start_log
         return unless @config.log_level

         directory = @config.log_dir

         log_path = directory + 'queue-manager.log'

         directory.mkpath
         File.open(log_path.to_path, 'a+') { |f| f.write '' }

         logger = Logger.new(log_path.to_path)

         logger.level = @config.log_level

         # @logger.info(['',
         #               '===================================',
         #               "Started worker process, #{long_name}, to work off queue #{@queue.name}.",
         #               "Worker pid=#{Process.pid}; parent pid=#{Process.ppid}.",
         #               '==================================='].join("\n"))

         logger
      end

      # Methods exclusive to the child process
      module ChildMethods
         def deamonize(name)
            Process.daemon(true)
            Process.setsid
            srand
            Process.setproctitle(name)
            close_io

            write_pid_file(Process.pid, name)

            @config.run_process_block
         end

         # Make sure all input/output streams are closed
         def close_io
            stds = [$stdin, $stdout, $stderr]

            # Part 1: close all IO objects (except for $stdin/$stdout/$stderr)
            ObjectSpace.each_object(IO) do |io|
               next if stds.include?(io)

               begin
                  io.close
               rescue IOError
                  next
               end
            end

            # Part 2: redirect STD connections
            stds.each do |io|
               io.reopen '/dev/null'
            end

            # TODO: redirect OUT or ERR to logger?
         end

         # Wrapping #exit to allow for tests to easily stub out this behaviour.
         # If #exit isn't prevented, the test framework will break,
         # but #exit can't be directly stubbed either (because it's a required Kernel method)
         def shutdown_worker
            exit
         end
      end

      # Methods exclusive to the main/parent process
      module ParentMethods
         def kill_old_workers
            @config.pid_dir.mkpath

            @config.pid_dir.each_child do |file|
               pid = file.read.to_i

               begin
                  Process.kill('KILL', pid)
                  @logger.info("Killing old worker process pid: #{ pid }")
               rescue Errno::ESRCH
                  @logger.info("Expected old worker process pid=#{ pid }, but none was found")
               end

               file.delete
            end
         end

         def write_pid_file(pid, filename)
            @config.pid_dir.mkpath

            pid_file = @config.pid_dir + "#{ filename }.pid"

            File.open(pid_file.to_path, 'w') do |f|
               f.print(pid)
            end
         end

         def check_for_name(name)
            # better to use backticks so we can get the info and not spam user's stdout
            warn <<~WARNING unless `pgrep -f #{ name }`.empty?
               Warning: there is another process named "#{ name }". Use #each_process(prefix: '') in
                        Procrastinator setup if you want to help yourself distinguish them.
            WARNING
         end
      end

      include ChildMethods
      include ParentMethods
   end
end
