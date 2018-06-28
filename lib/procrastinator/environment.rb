module Procrastinator
   class Environment
      attr_reader :queue_workers, :processes

      DEFAULT_LOG_DIRECTORY = 'log/'

      def initialize(config)
         @queue_workers = []
         @processes     = []

         @config = config

         @task_loader = config.loader
      end

      def spawn_workers
         @config.queues.each do |name, props|
            if @config.test_mode?
               @queue_workers << QueueWorker.new(props.merge(name:         name,
                                                             task_context: @config.context,
                                                             persister:    @task_loader))
            else
               pid = fork

               if pid
                  # === PARENT PROCESS ===
                  Process.detach(pid)
                  @processes << pid
               else
                  # === CHILD PROCESS ===
                  # Create a new task loader because the one from the parent is now async and unreliable
                  @task_loader = @config.loader

                  worker = QueueWorker.new(props.merge(name:         name,
                                                       persister:    @task_loader,
                                                       task_context: @config.context,
                                                       log_dir:      @config.log_dir,
                                                       log_level:    @config.log_level))

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
      end

      def act(*queue_names)
         unless @config.test_mode?
            err = <<~ERR
               Procrastinator.act called outside Test Mode. 
               Either use Procrastinator.spawn_workers or call #enable_test_mode in Procrastinator.setup.
            ERR

            raise RuntimeError.new(err)
         end

         if queue_names.empty?
            @queue_workers.each do |worker|
               worker.act
            end
         else
            queue_names.each do |name|
               @queue_workers.find {|worker| worker.name == name}.act
            end
         end
      end

      def delay(queue = nil, data: nil, run_at: Time.now.to_i, expire_at: nil)
         if queue.nil? && @config.many_queues?
            err = %[queue must be specified when more than one is registered. Defined queues are: #{@config.queues_string}]

            raise ArgumentError.new(err)
         end

         queue ||= @config.queues.keys.first

         if @config.queues[queue].nil?
            err = %[there is no :#{queue} queue registered. Defined queues are: #{@config.queues_string}]

            raise ArgumentError.new(err)
         end

         @task_loader.create_task(queues:         queue,
                                  run_at:         run_at.to_i,
                                  initial_run_at: run_at.to_i,
                                  expire_at:      expire_at.nil? ? nil : expire_at.to_i,
                                  data:           YAML.dump(data))
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

   class MalformedTaskLoaderError < StandardError
   end
end