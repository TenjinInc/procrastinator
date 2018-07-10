module Procrastinator
   class QueueManager
      attr_reader :workers

      def initialize(config)
         # Workers is either QueueWorkers directly or process IDs for their wrapping process
         @workers = []

         @config = config
      end

      def spawn_workers
         scheduler = Scheduler.new(@config)
         loader    = @config.loader

         @config.queues.each do |queue|
            if @config.test_mode?
               @workers << QueueWorker.new(queue:        queue,
                                           task_context: @config.context,
                                           scheduler:    scheduler,
                                           persister:    loader)
            else
               pid = fork

               if pid
                  # === PARENT PROCESS ===
                  Process.detach(pid)
                  @workers << pid
               else
                  # === CHILD PROCESS ===
                  @config.run_process_block

                  worker = QueueWorker.new(queue:        queue,
                                           task_context: @config.context,
                                           scheduler:    scheduler,
                                           persister:    @config.loader,
                                           log_dir:      @config.log_dir,
                                           log_level:    @config.log_level)

                  title = if @config.prefix
                             "#{@config.prefix}-#{worker.long_name}"
                          else
                             worker.long_name
                          end

                  Process.setproctitle(title)

                  monitor_parent(worker)

                  worker.work
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

         if queue_names.empty?
            @workers.each do |worker|
               worker.act
            end
         else
            queue_names.each do |name|
               @workers.find {|worker| worker.name == name}.act
            end
         end
      end

      private

      def monitor_parent(worker)
         parent_pid = Process.ppid

         heartbeat_thread = Thread.new(parent_pid) do |ppid|
            loop do
               begin
                  Process.kill(0, ppid) # kill with 0 flag checks if the process exists & has permissions
               rescue Errno::ESRCH
                  worker.log_parent_exit(ppid: ppid, pid: Process.pid)
                  exit
               end

               sleep(5)
            end
         end

         heartbeat_thread.abort_on_exception = true
      end
   end
end