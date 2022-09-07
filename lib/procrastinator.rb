# frozen_string_literal: true

require 'procrastinator/version'
require 'procrastinator/loggable'
require 'procrastinator/task_meta_data'
require 'procrastinator/logged_task'
require 'procrastinator/queue'
require 'procrastinator/queue_worker'
require 'procrastinator/config'
require 'procrastinator/task'
require 'procrastinator/scheduler'
require 'procrastinator/task_store/file_transaction'
require 'procrastinator/task_store/simple_comma_store'

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
      raise ArgumentError, 'Procrastinator.setup must be given a block' unless block

      config = Config.new(&block)

      raise SetupError, SetupError::ERR_NO_QUEUE if config.queues.empty?

      Scheduler.new(config)
   end

   class SetupError < RuntimeError
      ERR_NO_QUEUE = 'setup block must call #define_queue on the environment'
   end
end
