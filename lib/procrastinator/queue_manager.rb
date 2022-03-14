# frozen_string_literal: true

module Procrastinator
   # Spawns and manages work queue subprocesses.
   #
   # This is where all of the multi-process logic should be kept to.
   #
   # @author Robin Miller
   #
   # @!attribute [r] :workers
   #    @return [Hash] Maps the constructed QueueWorkers to their process ID.
   class QueueManager
      attr_reader :workers

      def initialize(config)
         @workers = {}
         @config  = config
      end

      # Spawns a new worker thread for each queue defined in the config
      #
      # @param queue_names [Array<String,Symbol>] Names of specific queues to act upon. Omit or leave empty to act on all queues.
      def work(*queue_names)
         QueueWorkerProxy.new(filter_queues(queue_names).collect do |queue|
            QueueWorker.new(queue: queue, config: @config)
         end)
      end

      # Provides a more natural chained syntax for kicking off the queue working process
      #
      # @see QueueManager#work
      class QueueWorkerProxy
         DEFAULT_PID_DIR = Pathname.new('pid/').freeze

         def initialize(workers)
            @workers = workers
         end

         # Work off the given number of tasks for each queue and return
         def stepwise(steps = 1)
            steps.times do
               @workers.each(&:act)
            end
         end

         # Work off jobs per queue until they are complete, with each queue on its own thread
         def threaded(timeout: nil)
            threads = @workers.collect do |worker|
               Thread.new do
                  worker.work
               end
            end

            threads.each { |t| t.join(timeout) }
         end

         # Consumes the current process and turns it into a background daemon.
         def deamonize
            raise 'not implemented yet'

            # TODO: it should write its pid file
            # TODO: it should clean up the pid file on clean exit
            # TODO: it should respond to SIGTERM to exit cleanly
         end
      end

      private

      # Find Queues that match the given queue names, or all queues if no names provided.
      # @param :queue_names [Array<String,Symbol>] List of queue names to match. If empty, will return all queues.
      def filter_queues(queue_names)
         queue_names ||= []

         @config.queues.select do |queue|
            queue_names.empty? || queue_names.include?(queue.name)
         end
      end
   end
end
