module Procrastinator
   class Scheduler
      def initialize(config)
         @config = config
      end

      def delay(queue = nil, data: nil, run_at: Time.now.to_i, expire_at: nil)
         queue_name = queue
         queue_list = @config.queues_string

         if queue_name.nil? && @config.multiqueue?
            err = "queue must be specified when more than one is registered. Defined queues are: #{queue_list}"

            raise ArgumentError.new(err)
         end

         queue_name = @config.queue.name if @config.single_queue?

         queue = @config.queue(name: queue_name)

         unless queue
            raise ArgumentError.new("there is no :#{queue_name} queue registered. Defined queues are: #{queue_list}")
         end

         if data.nil? && queue.task_class.method_defined?(:data=)
            raise ArgumentError.new("task #{queue.task_class} expects to receive :data. Provide :data to #delay.")
         end

         if !data.nil? && !queue.task_class.method_defined?(:data=)
            err = <<~ERROR
               task #{queue.task_class} does not import :data. Add this in your class definition: 
                     import_test_data :data
            ERROR

            raise ArgumentError.new(err)
         end

         loader.create_task(queue:          queue_name,
                            run_at:         run_at.to_i,
                            initial_run_at: run_at.to_i,
                            expire_at:      expire_at.nil? ? nil : expire_at.to_i,
                            data:           YAML.dump(data))
      end

      private

      # Scheduler must always get the loader indirectly. If it saves the loader to an instance variable,
      # then that could hold a reference to a bad (ie. gone) connection on the previous process
      def loader
         @config.loader
      end
   end
end