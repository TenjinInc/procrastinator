require 'procrastinator/version'
require 'procrastinator/queue_worker'
require 'procrastinator/task_worker'


module Procrastinator


   def self.setup(persister, queues)
      raise ArgumentError.new('persister cannot be nil') if persister.nil?
      raise ArgumentError.new('queue definitions cannot be nil') if queues.nil?
      raise ArgumentError.new('queue definition hash is empty') if queues.empty?

      [:read_tasks, :create_task, :update_task, :delete_task].each do |method|
         raise MalformedPersisterError.new("persister must repond to ##{method}") unless persister.respond_to? method
      end
   end


   class Environment
      # TODO: code sketch
      # def self.spawn_worker
      #    pid = fork do
      #       while true do
      #          read
      #       end
      #    end
      #
      #    Process.detach(pid)
      # end
   end

   class MalformedPersisterError < StandardError
   end
end
