# frozen_string_literal: true

require 'procrastinator/version'
require 'procrastinator/task_meta_data'
require 'procrastinator/task_worker'
require 'procrastinator/queue'
require 'procrastinator/queue_worker'
require 'procrastinator/config'
require 'procrastinator/queue_manager'
require 'procrastinator/task'
require 'procrastinator/scheduler'
require 'procrastinator/loaders/csv_loader'

require 'logger'
require 'pathname'

# Top-level module for the Procrastinator Gem.
#
# Call Procrastinator.setup with a block to initialize and run independent worker sub processes to complete tasks
# asynchronously from your main application.
#
# Read the README for details.
#
# @author Robin Miller
#
# @see https://github.com/TenjinInc/procrastinator
module Procrastinator
   # rubocop:disable Style/ClassVars
   @@test_mode = false

   def self.test_mode=(value)
      @@test_mode = value
   end

   def self.test_mode
      @@test_mode
   end

   # rubocop:enable Style/ClassVars

   # Creates a configuration object and passes it into the given block.
   #
   # @yield the created configuration object
   def self.setup(&block)
      raise ArgumentError, 'Procrastinator.setup must be given a block' unless block_given?

      config = Config.new

      config.setup(@@test_mode, &block)

      QueueManager.new(config).spawn_workers
   end
end
