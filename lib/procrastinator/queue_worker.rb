module Procrastinator
   class QueueWorker
      extend Forwardable

      def_delegators :@queue, :name

      # expected methods for all persistence strategies
      PERSISTER_METHODS = [:read, :update, :delete]

      def initialize(queue:,
                     persister:,
                     scheduler: nil,
                     task_context: nil,
                     log_dir: nil,
                     log_level: Logger::INFO)
         raise ArgumentError.new(':persister may not be nil') unless persister

         PERSISTER_METHODS.each do |method|
            err = "The supplied IO object must respond to ##{method}"

            raise(MalformedTaskPersisterError.new(err)) unless persister.respond_to? method
         end

         @queue        = queue
         @persister    = persister
         @task_context = task_context
         @scheduler    = scheduler

         start_log(log_dir, level: log_level)
      end

      def work
         begin
            loop do
               sleep(@queue.update_period)

               act
            end
         rescue StandardError => e
            if @logger
               @logger.fatal(e)
            else
               raise e
            end
         end
      end

      def act
         # shuffling and re-sorting to avoid worst case O(n^2) when receiving already sorted data
         # on quicksort (which is default ruby sort). It is not unreasonable that the persister could return sorted
         # results
         # Ideally, we'd use a better algo than qsort for this, but this will do for now
         tasks = @persister.read(queue: @queue.name)

         tasks = tasks.reject {|t| t[:run_at].nil?}.shuffle.sort_by {|t| t[:run_at]}

         tasks = tasks.collect do |t|
            t.delete_if {|key| !TaskMetaData::EXPECTED_DATA.include?(key)}
         end

         tasks.first(@queue.max_tasks).each do |task_hash|
            metadata = TaskMetaData.new(task_hash)

            if metadata.runnable?
               tw = TaskWorker.new(metadata:  metadata,
                                   queue:     @queue,
                                   scheduler: @scheduler,
                                   context:   @task_context,
                                   logger:    @logger)

               tw.work

               if tw.successful?
                  @persister.delete(metadata.id)
               else
                  @persister.update(metadata.id, tw.to_h.merge(queue: @queue.name))
               end
            end
         end
      end

      def long_name
         "#{@queue.name}-queue-worker"
      end

      # Starts a log file and stores the logger within this queue worker.
      #
      # Separate from init because logging is context-dependent
      def start_log(directory, level: Logger::INFO)
         if directory
            log_path = Pathname.new("#{directory}/#{long_name}.log")

            log_path.dirname.mkpath
            File.open(log_path.to_path, 'a+') do |f|
               f.write ''
            end

            @logger = Logger.new(log_path.to_path)

            @logger.level = level

            @logger.info(['',
                          '===================================',
                          "Started worker process, #{long_name}, to work off queue #{@queue.name}.",
                          "Worker pid=#{Process.pid}; parent pid=#{Process.ppid}.",
                          '==================================='].join("\n"))
         end
      end

      # Logs a termination due to parent process termination
      #
      # == Parameters:
      # @param ppid the parent's process id
      # @param pid the child's process id
      #
      def log_parent_exit(ppid:, pid:)
         raise RuntimeError.new('Cannot log when logger not defined. Call #start_log first.') unless @logger

         @logger.error("Terminated worker process (pid=#{pid}) due to main process (ppid=#{ppid}) disappearing.")
      end
   end

   class MalformedTaskPersisterError < StandardError
   end
end