# frozen_string_literal: true

module Procrastinator
   # A QueueWorker checks for tasks to run from the task store and executes them, updating information in the task
   # store as necessary.
   #
   # @author Robin Miller
   class QueueWorker
      extend Forwardable

      def_delegators :@queue, :name, :next_task

      # expected methods for all persistence strategies
      PERSISTER_METHODS = [:read, :update, :delete].freeze

      def initialize(queue:, config:)
         raise ArgumentError, ':queue cannot be nil' if queue.nil?
         raise ArgumentError, ':config cannot be nil' if config.nil?

         @config = config

         @queue = if queue.is_a? Symbol
                     config.queue(name: queue)
                  else
                     queue
                  end

         @scheduler = Scheduler.new(config)
         @logger    = Logger.new(StringIO.new)
      end

      # Works on jobs forever
      def work!
         @logger = open_log!("#{ name }-queue-worker", @config)
         @logger.info("Started worker thread to consume queue: #{ name }")

         loop do
            sleep(@queue.update_period)

            work_one
         end
      rescue StandardError => e
         @logger.fatal(e)

         raise
      end

      # Performs exactly one task on the queue
      def work_one
         task = next_task(logger:    @logger,
                          container: @config.container,
                          scheduler: @scheduler) || return

         begin
            task.run

            @queue.delete(task.id)
         rescue StandardError => e
            task.fail(e)

            task_info = task.to_h
            id        = task_info.delete(:id)
            @queue.update(id, **task_info)
         end
      end

      # Logs halting the queue
      def halt
         @logger&.info("Halted worker on queue: #{ name }")
         @logger&.close
      end

      # Starts a log file and returns the created Logger
      def open_log!(name, config)
         return @logger unless config.log_level

         log_path = config.log_dir / "#{ name }.log"

         config.log_dir.mkpath
         FileUtils.touch(log_path)

         Logger.new(log_path.to_path,
                    config.log_shift_age, config.log_shift_size,
                    level:     config.log_level || Logger::FATAL,
                    progname:  name,
                    formatter: Config::DEFAULT_LOG_FORMATTER)
      end
   end

   # Raised when a Task Storage strategy is missing a required part of the API.
   #
   # @see TaskStore
   class MalformedTaskPersisterError < RuntimeError
   end
end
