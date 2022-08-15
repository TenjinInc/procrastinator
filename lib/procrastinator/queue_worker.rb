# frozen_string_literal: true

module Procrastinator
   # A QueueWorker checks for tasks to run from the loader defined in the provided config and executes them,
   # updating information in the task loader as necessary.
   #
   # @author Robin Miller
   class QueueWorker
      extend Forwardable

      include Loggable

      def_delegators :@queue, :name

      # expected methods for all persistence strategies
      PERSISTER_METHODS = [:read, :update, :delete].freeze

      def initialize(queue:, config:)
         @queue     = queue
         @config    = config
         @scheduler = Scheduler.new(config)
      end

      # Works on jobs forever
      def work
         @logger = open_log!("#{ @queue.name }-queue-worker", @config)

         @logger&.info("Started worker thread to consume queue: #{ @queue.name }")

         begin
            loop do
               sleep(@queue.update_period)

               work_one
            end
         rescue StandardError => e
            raise unless @logger

            @logger.fatal(e)
         end
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
            @config.loader.delete(worker.id)
         else
            worker_info = worker.to_h
            id          = worker_info.delete(:id)
            @config.loader.update(id, **worker_info)
         end
      end

      private

      def fetch_task
         tasks = @config.loader.read(queue: @queue.name).map(&:to_h).reject { |t| t[:run_at].nil? }

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
