module Procrastinator
   class QueueWorker
      DEFAULT_TIMEOUT       = 3600 # seconds = one hour
      DEFAULT_MAX_ATTEMPTS  = 20
      DEFAULT_UPDATE_PERIOD = 10 # seconds
      DEFAULT_MAX_TASKS     = 10

      attr_reader :name, :timeout, :max_attempts, :update_period, :max_tasks

      # Timeout is in seconds
      def initialize(name:,
                     persister:,
                     max_attempts: DEFAULT_MAX_ATTEMPTS,
                     timeout: DEFAULT_TIMEOUT,
                     update_period: DEFAULT_UPDATE_PERIOD,
                     max_tasks: DEFAULT_MAX_TASKS)
         raise ArgumentError.new('Queue name may not be nil') unless name
         raise ArgumentError.new('Persister may not be nil') unless persister

         raise(MalformedTaskPersisterError.new('The supplied IO object must respond to #read_tasks')) unless persister.respond_to? :read_tasks
         raise(MalformedTaskPersisterError.new('The supplied IO object must respond to #update_task')) unless persister.respond_to? :update_task
         raise(MalformedTaskPersisterError.new('The supplied IO object must respond to #delete_task')) unless persister.respond_to? :delete_task


         @name          = name.to_s.gsub(/\s/, '_').to_sym
         @timeout       = timeout
         @max_attempts  = max_attempts
         @update_period = update_period
         @max_tasks     = max_tasks
         @persister     = persister
      end

      def work
         loop do
            sleep(@update_period)

            # shuffling and re-sorting to avoid worst case O(n^2) on quicksort
            # when receiving already sorted data. Ideally, we'd use a better algo, but this will do for now
            tasks = @persister.read_tasks(@name).shuffle.sort_by { |t| t[:run_at] }

            tasks.first(@max_tasks).each do |task_data|
               if Time.now.to_i >= task_data[:run_at].to_i
                  parsed_data = task_data
                  id          = parsed_data.delete(:id)

                  tw = TaskWorker.new(parsed_data)

                  tw.work

                  if tw.status == :success
                     @persister.delete_task(id)
                  else
                     @persister.update_task(tw.to_hash.merge(run_at: task_data[:run_at], queue: @name))
                  end
               end
            end
         end
      end
   end

   class MalformedTaskPersisterError < StandardError
   end
end