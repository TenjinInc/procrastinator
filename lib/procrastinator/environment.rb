module Procrastinator
   class Environment
      attr_reader :persister, :queue_definitions, :queue_workers, :processes, :test_mode

      DEFAULT_LOG_DIRECTORY = 'log/'

      def initialize(persister:, test_mode: false)
         raise ArgumentError.new('persister cannot be nil') if persister.nil?

         [:read_tasks, :create_task, :update_task, :delete_task].each do |method|
            raise MalformedPersisterError.new("persister must repond to ##{method}") unless persister.respond_to? method
         end

         @persister         = persister
         @test_mode         = test_mode
         @queue_definitions = {}
         @queue_workers     = []
         @processes         = []
         @log_dir           = DEFAULT_LOG_DIRECTORY
      end

      def define_queue(name, properties={})
         raise ArgumentError.new('queue name cannot be nil') if name.nil?

         @queue_definitions[name] = properties
      end

      def spawn_workers
         if @test_mode
            @queue_definitions.each do |name, props|
               @queue_workers << QueueWorker.new(props.merge(name:      name,
                                                             persister: @persister,
                                                             log_dir:   @log_dir))
            end
         else
            @queue_definitions.each do |name, props|
               parent_pid = Process.pid

               pid = fork do
                  worker = QueueWorker.new(props.merge(name:      name,
                                                       persister: @persister,
                                                       log_dir:   @log_dir))

                  worker.start_log

                  Process.setproctitle(worker.long_name) # tODO: add an app name prefix

                  monitor_parent(parent_pid, worker)

                  worker.work
               end

               Process.detach(pid) unless pid.nil?
               @processes << pid
            end
         end
      end

      def act(*queue_names)
         unless @test_mode
            raise RuntimeError.new('Procrastinator.act called outside Test Mode. Enable test mode by setting Procrastinator.test_mode = true before running setup')
         end

         if queue_names.empty?
            @queue_workers.each do |worker|
               worker.act
            end
         else
            queue_names.each do |name|
               @queue_workers.find { |worker| worker.name == name }.act
            end
         end
      end

      def delay(queue: nil, run_at: Time.now.to_i, expire_at: nil, task:)
         raise ArgumentError.new('task may not be nil') if task.nil?
         raise MalformedTaskError.new('the provided task does not support #run method') unless task.respond_to? :run

         # We're checking these on init because it's one of those extremely rare cases where you'd want to know
         # incredibly early, because of the sub-processing. It's a bit belt-and suspenders, but UX is important for
         # devs, too.
         [:success, :fail, :final_fail].each do |method_name|
            if task.respond_to?(method_name) && task.method(method_name).arity <= 0
               raise MalformedTaskError.new("the provided task must accept a parameter to its ##{method_name} method")
            end
         end

         if queue.nil? && @queue_definitions.size > 1
            raise ArgumentError.new("queue must be specified when more than one is registered. Defined queues are: #{queue_definitions.keys.map { |k| ':' + k.to_s }.join(', ')}")
         else
            queue ||= @queue_definitions.keys.first
            raise ArgumentError.new(%Q{there is no "#{queue}" queue registered in this environment}) if @queue_definitions[queue].nil?
         end

         @persister.create_task(queue:          queue,
                                run_at:         run_at.to_i,
                                initial_run_at: run_at.to_i,
                                expire_at:      expire_at.nil? ? nil : expire_at.to_i,
                                task:           YAML.dump(task))
      end

      def enable_test_mode
         @test_mode = true
      end

      def log_dir(path)
         @log_dir = path
      end

      private
      def monitor_parent(parent_pid, worker)
         heartbeat_thread = Thread.new(parent_pid) do |pid|
            loop do
               begin
                  Process.kill(0, pid) # kill(0) will check if the process exists
               rescue Errno::ESRCH
                  worker.log_parent_exit
                  exit
               end

               sleep(5)
            end
         end

         heartbeat_thread.abort_on_exception = true
      end
   end

   class MalformedPersisterError < StandardError
   end
end