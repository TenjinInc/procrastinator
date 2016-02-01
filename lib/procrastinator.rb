require 'procrastinator/version'
require 'procrastinator/queue_worker'
require 'procrastinator/task_worker'


module Procrastinator
   def self.setup(persister, queues)
      env = Environment.new(persister, queues)

      env.spawn_workers

      env
   end

   def self.spawn_workers(env)
      env.queues.each
   end

   class Environment
      attr_reader :persister, :queues

      def initialize(persister, queues)
         raise ArgumentError.new('persister cannot be nil') if persister.nil?
         raise ArgumentError.new('queue definitions cannot be nil') if queues.nil?
         raise ArgumentError.new('queue definition hash is empty') if queues.empty?

         [:read_tasks, :create_task, :update_task, :delete_task].each do |method|
            raise MalformedPersisterError.new("persister must repond to ##{method}") unless persister.respond_to? method
         end

         @persister = persister
         @queues    = queues
      end

      def spawn_workers
         @queues.each do |name, props|
            pid = fork do
               Process.setproctitle("#{name}-queue-worker")

               worker = QueueWorker.new(props.merge(name: name, persister: @persister))

               # worker.work
            end

            Process.detach(pid) unless pid.nil?
            #    @sub_processes << pid
         end
      end
   end

   class MalformedPersisterError < StandardError
   end
end
