require 'pathname'

module Procrastinator
   class QueueManager
      attr_reader :workers

      def initialize(config)
         # Workers is either QueueWorkers directly or process IDs for their wrapping process
         @workers = {}

         @config = config

         @logger = start_log(config.log_dir, @config.log_level)
      end

      def spawn_workers
         scheduler = Scheduler.new(@config)

         pid_dir = Pathname.new(@config.pid_dir)

         pid_dir.mkpath
         pid_dir.each_child do |file|
            pid = file.read.to_i

            begin
               Process.kill('KILL', pid)
               @logger.info("Killing old worker process pid: #{pid}")
            rescue Errno::ESRCH
               @logger.info("Expected old worker process pid=#{pid}, but none was found")
            end

            file.delete
         end

         if ENV['PROCRASTINATOR_STOP']
            @logger.warn('Cannot spawn queue workers because environment variable PROCRASTINATOR_STOP is set')
         else
            @config.queues.each do |queue|
               worker = QueueWorker.new(queue:     queue,
                                        config:    @config,
                                        scheduler: scheduler)
               if @config.test_mode?
                  @workers[worker] = Process.pid
               else
                  pid = fork

                  if pid
                     # === PARENT PROCESS ===
                     Process.detach(pid)
                     @workers[worker] = pid
                     write_pid_file(pid, worker.long_name)
                  else
                     # === CHILD PROCESS ===
                     Process.setproctitle(worker.long_name)

                     @config.run_process_block

                     worker.work
                     shutdown_worker
                  end
               end
            end
         end

         scheduler
      end

      def act(*queue_names)
         unless @config.test_mode?
            err = <<~ERR
               Procrastinator.act called outside Test Mode. 
               Either use Procrastinator.spawn_workers or call #enable_test_mode in Procrastinator.setup.
            ERR

            raise RuntimeError, err
         end

         workers = @workers.keys

         if queue_names.empty?
            workers.each do |worker|
               worker.act
            end
         else
            queue_names.each do |name|
               workers.find {|worker| worker.name == name}.act
            end
         end
      end

      private

      # Wrapping #exit to allow for tests to easily stub out this behaviour.
      # If #exit isn't prevented, the test framework will break,
      # but #exit can't be directly stubbed either (because it's a required Kernel method)
      def shutdown_worker
         exit
      end

      def write_pid_file(pid, filename)
         pid_file = "#{@config.pid_dir}/#{filename}.pid"

         File.open(pid_file, 'w') do |f|
            f.print(pid)
         end
      end

      def start_log(directory, level)
         return unless directory

         log_path = Pathname.new("#{directory}/queue-manager.log")

         log_path.dirname.mkpath
         File.open(log_path.to_path, 'a+') {|f| f.write ''}

         logger = Logger.new(log_path.to_path)

         logger.level = level

         # @logger.info(['',
         #               '===================================',
         #               "Started worker process, #{long_name}, to work off queue #{@queue.name}.",
         #               "Worker pid=#{Process.pid}; parent pid=#{Process.ppid}.",
         #               '==================================='].join("\n"))

         logger
      end
   end
end