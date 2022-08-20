# frozen_string_literal: true

module Procrastinator
   # A QueueWorker checks for tasks to run from the task store and executes them, updating information in the task
   # store as necessary.
   #
   # @author Robin Miller
   class QueueWorker
      extend Forwardable

      include Loggable

      def_delegators :@queue, :name

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

         # freeze
      end

      # Works on jobs forever
      def work
         @logger = open_log!("#{ @queue.name }-queue-worker", @config)

         @logger&.info("Started worker thread to consume queue: #{ @queue.name }")

         loop do
            sleep(@queue.update_period)

            work_one
         end
      rescue StandardError => e
         raise unless @logger

         @logger.fatal(e)
      end

      # Performs exactly one task on the queue
      def work_one
         metadata = fetch_task
         return unless metadata

         worker = TaskWorker.new(metadata:  metadata,
                                 queue:     @queue,
                                 scheduler: @scheduler,
                                 container: @config.container,
                                 logger:    @logger)

         worker.work

         if worker.successful?
            @queue.delete(worker.id)
         else
            worker_info = worker.to_h
            id          = worker_info.delete(:id)
            @queue.update(id, **worker_info)
         end
      end

      def halt
         @logger&.info("Halted worker on queue: #{ name }")
         @logger&.close
      end

      private

      def fetch_task
         tasks = @queue.read(queue: name).map(&:to_h).reject { |t| t[:run_at].nil? }

         metas = sort_tasks(tasks).collect do |t|
            TaskMetaData.new(t.delete_if { |key| !TaskMetaData::EXPECTED_DATA.include?(key) })
         end

         metas.find(&:runnable?)
      end

      def sort_tasks(tasks)
         # shuffling and re-sorting to avoid worst case O(n^2) when receiving already sorted data
         # on quicksort (which is default ruby sort). It is not unreasonable that the persister could return sorted
         # results
         # Ideally, we'd use a better algo than qsort for this, but this will do for now
         tasks.shuffle.sort_by { |t| t[:run_at] }
      end
   end

   class MalformedTaskPersisterError < StandardError
   end
end
