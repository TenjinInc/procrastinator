module Procrastinator
   class QueueWorker
      DEFAULT_TIMEOUT       = 3600 # in seconds; one hour total
      DEFAULT_MAX_ATTEMPTS  = 20
      DEFAULT_UPDATE_PERIOD = 10 # seconds
      DEFAULT_MAX_TASKS     = 10

      attr_reader :name, :timeout, :max_attempts, :update_period, :max_tasks

      # Timeout is in seconds
      def initialize(name:,
                     persister:,
                     task_class:,
                     task_context: nil,
                     log_dir: nil,
                     log_level: Logger::INFO,
                     max_attempts: DEFAULT_MAX_ATTEMPTS,
                     timeout: DEFAULT_TIMEOUT,
                     update_period: DEFAULT_UPDATE_PERIOD,
                     max_tasks: DEFAULT_MAX_TASKS)
         raise ArgumentError.new(':name may not be nil') unless name
         raise ArgumentError.new(':task_class may not be nil') unless task_class
         raise ArgumentError.new(':persister may not be nil') unless persister

         raise ArgumentError.new('Task class must be initializable') unless task_class.respond_to? :new

         raise(MalformedTaskPersisterError.new('The supplied IO object must respond to #read_tasks')) unless persister.respond_to? :read_tasks
         raise(MalformedTaskPersisterError.new('The supplied IO object must respond to #update_task')) unless persister.respond_to? :update_task
         raise(MalformedTaskPersisterError.new('The supplied IO object must respond to #delete_task')) unless persister.respond_to? :delete_task

         @name          = name.to_s.gsub(/\s/, '_').to_sym
         @timeout       = timeout
         @max_attempts  = max_attempts
         @update_period = update_period
         @max_tasks     = max_tasks
         @persister     = persister
         @task_context  = task_context
         @task_class    = task_class

         start_log(log_dir, level: log_level)
      end

      def work
         begin
            loop do
               sleep(@update_period)

               act
            end
         rescue StandardError => e
            @logger.fatal(e)
            # raise e
         end
      end

      def act
         # shuffling and re-sorting to avoid worst case O(n^2) when receiving already sorted data
         # on quicksort (which is default ruby sort). It is not unreasonable that the persister could return sorted
         # results
         # Ideally, we'd use a better algo than qsort for this, but this will do for now
         tasks = @persister.read_tasks(@name).reject {|t| t[:run_at].nil?}.shuffle.sort_by {|t| t[:run_at]}

         tasks.first(@max_tasks).each do |task_hash|
            if Time.now.to_i >= task_hash[:run_at].to_i
               tw = TaskWorker.new(task_hash.merge(task_class: @task_class))

               work_data          = {context: @task_context}
               work_data[:logger] = @logger if @logger

               tw.work(work_data)

               if tw.successful?
                  @persister.delete_task(task_hash[:id])
               else
                  @persister.update_task(tw.task_hash.merge(queue: @name))
               end
            end
         end
      end

      def long_name
         "#{@name}-queue-worker"
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
                          "Started worker process, #{long_name}, to work off queue #{@name}.",
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