# frozen_string_literal: true

require 'procrastinator/version'
require 'procrastinator/task_meta_data'
require 'procrastinator/task_worker'
require 'procrastinator/queue'
require 'procrastinator/queue_worker'
require 'procrastinator/config'
require 'procrastinator/task'
require 'procrastinator/scheduler'
require 'procrastinator/loaders/csv_loader'

require 'logger'
require 'pathname'

# Top-level module for the Procrastinator Gem.
#
# Call Procrastinator.setup with a block to configure task queues.
#
# See README for details.
#
# @author Robin Miller
#
# @see https://github.com/TenjinInc/procrastinator
module Procrastinator
   # Creates a configuration object and passes it into the given block.
   #
   # @yield the created configuration object
   # @return [Scheduler] a scheduler object that can be used to interact with the queues
   def self.setup(&block)
      raise ArgumentError, 'Procrastinator.setup must be given a block' unless block_given?

      config = Config.new

      config.setup(&block)

      Scheduler.new(config)
   end
end
