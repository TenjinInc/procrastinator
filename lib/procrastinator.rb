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

      raise RuntimeError.new('setup block must call #persister_factory on the environment') if env.persister.nil?
      raise RuntimeError.new('setup block must call #define_queue on the environment') if env.queue_definitions.empty?
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
