require 'procrastinator/version'
require 'procrastinator/queue_worker'
require 'procrastinator/task_worker'
require 'procrastinator/environment'
require 'logger'


module Procrastinator
   @@test_mode = false

   def self.setup(&block)
      raise ArgumentError.new('Procrastinator.setup must be given a block') if block.nil?

      env = Environment.new(test_mode: @@test_mode)

      yield(env)

      env.verify_configuration

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
