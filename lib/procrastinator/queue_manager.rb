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
      end

      # Spawns a new worker thread for each queue defined in the config
      #
      # @param queue_names [Array<String,Symbol>] Names of specific queues to act upon. Omit or leave empty to act on all queues.
      def work(*queue_names)
         QueueWorkerProxy.new(filter_queues(queue_names).collect do |queue|
            QueueWorker.new(queue: queue, config: @config)
         end)
      end

      # Provides a more natural chained syntax for kicking off the queue working process
      #
      # @see QueueManager#work
      class QueueWorkerProxy
         PID_EXT          = '.pid'
         DEFAULT_PID_DIR  = Pathname.new('pid/').freeze
         DEFAULT_PID_FILE = Pathname.new("procrastinator#{ PID_EXT }").freeze

         # 15 chars is linux limit
         MAX_PROC_LEN = 15

         def initialize(workers)
            @workers = workers
         end

         # Work off the given number of tasks for each queue and return
         def stepwise(steps = 1)
            steps.times do
               @workers.each(&:act)
            end
         end

         # Work off jobs per queue until they are complete, with each queue on its own thread
         def threaded(timeout: nil)
            threads = @workers.collect do |worker|
               Thread.new do
                  worker.work
               end
            end

            threads.each { |t| t.join(timeout) }
         end

         # Consumes the current process and turns it into a background daemon.
         #
         # @param name [String] The process name to request from the OS. Not guaranteed to be set, depending on OS support.
         # @param pid_path [Pathname|File|String] Path to where the process ID file is to be kept. Assumed to be a directory unless ends with '.pid'.
         def daemonize(name: nil, pid_path: nil)
            # double fork to guarantee no terminal can be attached.
            exit if fork
            Process.setsid
            exit if fork
            Dir.chdir '/' # allows process to continue even if the pwd of its running terminal disappears (eg deleted)

            warn('Starting Procrastinator...')

            manage_pid(pid_path)

            unless name.nil?
               warn "Warning: process name is longer than max length (#{ MAX_PROC_LEN }). Trimming to fit."
               name = name[0, MAX_PROC_LEN]

               warn "Warning: a process is already named \"#{ name }\". Consider the \"name:\" argument to distinguish."
               Process.setproctitle(name)
            end

            threaded

            warn("Procrastinator running. Process ID: #{ Process.pid }")
         end

         private

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
