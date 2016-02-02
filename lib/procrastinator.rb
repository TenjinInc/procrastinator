require 'procrastinator/version'
require 'procrastinator/queue_worker'
require 'procrastinator/task_worker'
require 'procrastinator/environment'


module Procrastinator
   def self.setup(persister, &block)
      raise ArgumentError.new('Procrastinator.setup must be given a block') if block.nil?

      env = Environment.new(persister)

      yield(env)

      raise RuntimeError.new('setup block did not define any queues') if env.queues.empty?

      env.spawn_workers

      env
   end
end
