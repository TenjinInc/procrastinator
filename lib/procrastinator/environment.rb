module Procrastinator
   class Environment
      attr_reader :task_loader_instance, :queue_definitions, :queue_workers, :processes, :test_mode

      DEFAULT_LOG_DIRECTORY = 'log/'

      def initialize(test_mode: false)
         @test_mode         = test_mode
         @queue_definitions = {}
         @queue_workers     = []
         @processes         = []
         @log_dir           = DEFAULT_LOG_DIRECTORY
         @log_level         = Logger::INFO
      end

      def verify_configuration
         raise RuntimeError.new('setup block must call #load_with on the environment') if @task_loader_factory.nil?
         raise RuntimeError.new('setup block must call #define_queue on the environment') if @queue_definitions.empty?
      end

      # Accepts a block that will be executed on the queue sub process. This is done to separate resource allocations
      # like database connections.
      # The result will be used to load tasks
      def load_with(&block)
         @task_loader_factory = block

         unless @task_loader_factory
            raise RuntimeError.new('#load_with must be given a block that produces a persistence handler for tasks')
         end

         # Start a loader for the parent to be able to #delay tasks
         init_task_loader
      end

      # Accepts a block that will be executed on the queue sub process.
      # The result will be passed into the task methods.
      def task_context(&block)
         @task_context_factory = block
      end

      def define_queue(name, task_class, properties = {})
         raise ArgumentError.new('queue name cannot be nil') if name.nil?
         raise ArgumentError.new('queue task class cannot be nil') if task_class.nil?
         raise MalformedTaskError.new("task #{task_class} does not support #run method") unless task_class.method_defined? :run

         # We're checking these on init because it's one of those extremely rare cases where you'd want to know early
         # because of the sub-processes. It's a bit belt-and suspenders, but UX is important for         # devs, too.
         expected_arity = {run: 2, success: 3, fail: 3, final_fail: 3}
         expected_arity.each do |method_name, arity|
            if task_class.method_defined?(method_name) && task_class.instance_method(method_name).arity < arity
               raise MalformedTaskError.new("the provided task must accept #{arity} parameters to its ##{method_name} method")
            end
         end

         @queue_definitions[name] = properties.merge(task_class: task_class)
      end

      def spawn_workers
         if @test_mode
            @queue_definitions.each do |name, props|
               props[:task_context] = @task_context_factory.call if @task_context_factory

               @queue_workers << QueueWorker.new(props.merge(name:      name,
                                                             persister: @task_loader_instance))
            end
         else
            @queue_definitions.each do |name, props|
               pid = fork

               if pid
                  # === PARENT PROCESS ===
                  Process.detach(pid)
                  @processes << pid
               else
                  # === CHILD PROCESS ===
                  # Create a new task loader because the one from the parent is now async and unreliable
                  init_task_loader

                  props[:task_context] = @task_context_factory.call if @task_context_factory

                  worker = QueueWorker.new(props.merge(name:      name,
                                                       persister: @task_loader_instance,
                                                       log_dir:   @log_dir,
                                                       log_level: @log_level))

                  Process.setproctitle("#{@process_prefix ? "#{@process_prefix}-" : ''}#{worker.long_name}")

                  monitor_parent(worker)

                  worker.work
               end
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
               @queue_workers.find {|worker| worker.name == name}.act
            end
         end
      end

      def delay(queue = nil, data: nil, run_at: Time.now.to_i, expire_at: nil)
         if queue.nil? && @queue_definitions.size > 1
            err = "queue must be specified when more than one is registered. Defined queues are: #{queue_symbols}"

            raise ArgumentError.new(err)
         else
            queue ||= @queue_definitions.keys.first
            if @queue_definitions[queue].nil?
               raise ArgumentError.new(%Q{there is no "#{queue}" queue registered in this environment})
            end
         end

         @task_loader_instance.create_task(queue:          queue,
                                           run_at:         run_at.to_i,
                                           initial_run_at: run_at.to_i,
                                           expire_at:      expire_at.nil? ? nil : expire_at.to_i,
                                           data:           YAML.dump(data))
      end

      def enable_test_mode
         @test_mode = true
      end

      def log_dir(path)
         @log_dir = path
      end

      def log_level(lvl)
         @log_level = lvl
      end

      def process_prefix(prefix)
         @process_prefix = prefix
      end

      def queue_symbols
         # if you .to_s a symbol, it drops the colon, so this is putting it back in
         queue_definitions.keys.map {|key| ":#{key}"}.join(', ')
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

      # This is called to construct a new task loader for this env.
      # It should be called for each fork as well,
      # so that they get distinct resources (eg. DB connections) from the parent process.
      def init_task_loader
         @task_loader_instance = @task_loader_factory.call

         raise ArgumentError.new('task loader cannot be nil') if @task_loader_instance.nil?

         [:read_tasks, :create_task, :update_task, :delete_task].each do |method|
            unless @task_loader_instance.respond_to? method
               raise MalformedPersisterError.new("task loader must repond to ##{method}")
            end
         end
      end
   end

   class MalformedPersisterError < StandardError
   end
end