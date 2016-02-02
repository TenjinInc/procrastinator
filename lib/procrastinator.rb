require 'procrastinator/version'
require 'procrastinator/queue_worker'
require 'procrastinator/task_worker'
require 'procrastinator/environment'


module Procrastinator
   def self.setup(persister, queues)
      env = Environment.new(persister, queues)

      env.spawn_workers

      env
   end
end
