module Procrastinator
   class Environment
      attr_reader :persister, :queue_definitions, :queue_workers, :processes, :test_mode

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
      end

      def define_queue(name, properties={})
         raise ArgumentError.new('queue name cannot be nil') if name.nil?

         @queue_definitions[name] = properties
      end

      def spawn_workers
         if @test_mode
            @queue_definitions.each do |name, props|
               @queue_workers << QueueWorker.new(props.merge(name: name, persister: @persister))
            end
         else
            @queue_definitions.each do |name, props|
               pid = fork do
                  Process.setproctitle("#{name}-queue-worker")

                  worker = QueueWorker.new(props.merge(name: name, persister: @persister))

                  monitor_parent

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
         raise MalformedTaskError.new('given task does not support #run method') unless task.respond_to? :run
         if queue.nil? && @queue_definitions.size > 1
            raise ArgumentError.new('queue must be specified when more than one is registered')
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

      private
      def monitor_parent
         heartbeat_thread = Thread.new(Process.ppid) do |ppid|
            loop do
               Process.kill 0, ppid

               sleep(5)
            end
         end

         heartbeat_thread.abort_on_exception = true
      end
   end

   class MalformedPersisterError < StandardError
   end
end