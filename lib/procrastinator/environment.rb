module Procrastinator
   class Environment
      attr_reader :persister, :queues, :processes


      def initialize(persister, queues)
         raise ArgumentError.new('persister cannot be nil') if persister.nil?
         raise ArgumentError.new('queue definitions cannot be nil') if queues.nil?
         raise ArgumentError.new('queue definition hash is empty') if queues.empty?

         [:read_tasks, :create_task, :update_task, :delete_task].each do |method|
            raise MalformedPersisterError.new("persister must repond to ##{method}") unless persister.respond_to? method
         end

         @persister = persister
         @queues    = queues
         @processes = []

         # Signal.trap('KILL') do
         #    cleanup
         # end

         # Signal.trap('TERM') do
         #    cleanup
         # end
         #
         # Signal.trap('QUIT') do
         #    cleanup
         # end
         #
         # Signal.trap('INT') do
         #    cleanup
         # end
      end

      def spawn_workers
         @queues.each do |name, props|
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