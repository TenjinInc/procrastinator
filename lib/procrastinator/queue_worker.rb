# frozen_string_literal: true

module Procrastinator
   # A QueueWorker checks for tasks to run from the loader defined in the provided config and executes them,
   # updating information in the task loader as necessary.
   #
   # @author Robin Miller
   class QueueWorker
      extend Forwardable

      def_delegators :@queue, :name

      # expected methods for all persistence strategies
      PERSISTER_METHODS = [:read, :update, :delete].freeze

      def initialize(queue:, config:, scheduler: nil)
         @queue     = queue
         @config    = config
         @scheduler = scheduler

         @logger = nil
      end

      def work
         start_log

         begin
            loop do
               sleep(@queue.update_period)

               act
            end
         rescue StandardError => e
            raise e unless @logger

            @logger.fatal(e)
         end
      end

      def act
         persister = @config.loader

         tasks = fetch_tasks(persister)

         tasks.each do |metadata|
            tw = TaskWorker.new(metadata:  metadata,
                                queue:     @queue,
                                scheduler: @scheduler,
                                context:   @config.context,
                                logger:    @logger)

            tw.work

            if tw.successful?
               persister.delete(metadata.id)
            else
               persister.update(metadata.id, tw.to_h.merge(queue: @queue.name.to_s))
            end
         end
      end

      def long_name
         name = "#{ @queue.name }-queue-worker"

         name = "#{ @config.prefix }-#{ name }" if @config.prefix

         name
      end

      # Starts a log file and stores the logger within this queue worker.
      #
      # Separate from init because logging is context-dependent
      def start_log
         return if @logger || !@config.log_dir

         log_path = @config.log_dir + "#{ long_name }.log"

         write_log_file(log_path)

         @logger = Logger.new(log_path.to_path)

         @logger.level = @config.log_level || Logger::INFO

         msg = <<~MSG
            ======================================================================
            Started worker process, #{ long_name }, to work off queue #{ @queue.name }.
            Worker pid=#{ Process.pid }; parent pid=#{ Process.ppid }.
            ======================================================================
         MSG

         @logger.info("\n#{ msg }")

         @logger
      end

      private

      def write_log_file(log_path)
         @config.log_dir.mkpath
         File.open(log_path.to_path, 'a+') do |f|
            f.write ''
         end
      end

      def fetch_tasks(persister)
         tasks = persister.read(queue: @queue.name).map(&:to_h).reject { |t| t[:run_at].nil? }

         tasks = sort_tasks(tasks)

         metas = tasks.collect do |t|
            TaskMetaData.new(t.delete_if { |key| !TaskMetaData::EXPECTED_DATA.include?(key) })
         end

         metas.select(&:runnable?)
      end

      def sort_tasks(tasks)
         # shuffling and re-sorting to avoid worst case O(n^2) when receiving already sorted data
         # on quicksort (which is default ruby sort). It is not unreasonable that the persister could return sorted
         # results
         # Ideally, we'd use a better algo than qsort for this, but this will do for now
         tasks.shuffle.sort_by { |t| t[:run_at] }.first(@queue.max_tasks)
      end
   end

   class MalformedTaskPersisterError < StandardError
   end
end
