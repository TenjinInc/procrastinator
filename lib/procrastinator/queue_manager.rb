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
      def spawn_workers
         # TODO: does it need to remember these workers? at all? or can they just be initted in the thread itself?
         @workers = @config.queues.collect do |queue|
            QueueWorker.new(queue:     queue,
                            config:    @config,
                            scheduler: Scheduler.new(@config))
         end

         @workers.each do |worker|
            Thread.new do
               worker.work
            end
         end
      end

      def act(*queue_names)
         @workers.each do |worker|
            worker.act if queue_names.empty? || queue_names.include?(worker.name)
         end
      end
   end
end
