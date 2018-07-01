require 'procrastinator/version'
require 'procrastinator/task_meta_data'
require 'procrastinator/task_worker'
require 'procrastinator/queue'
require 'procrastinator/queue_worker'
require 'procrastinator/config'
require 'procrastinator/queue_manager'
require 'procrastinator/task'
require 'logger'


module Procrastinator
   @@test_mode = false

   def self.setup(&block)
      raise ArgumentError.new('Procrastinator.setup must be given a block') if block.nil?

      config = Config.new

      yield(config)

      config.enable_test_mode if @@test_mode

      config.verify

      env = QueueManager.new(config)

      env.spawn_workers

      env
   end

   def self.test_mode=(value)
      @@test_mode = value
   end

   def self.test_mode
      @@test_mode
   end
end
