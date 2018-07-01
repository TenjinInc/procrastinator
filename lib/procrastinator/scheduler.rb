module Procrastinator
   class Scheduler
      def initialize(config)
         @config = config
      end

      def delay(queue = nil, data: nil, run_at: Time.now.to_i, expire_at: nil)
         if queue.nil? && @config.multiqueue?
            err = %[queue must be specified when more than one is registered. Defined queues are: #{@config.queues_string}]

            raise ArgumentError.new(err)
         end

         queue = @config.queue.name if @config.single_queue?

         unless @config.queue(name: queue)
            err = %[there is no :#{queue} queue registered. Defined queues are: #{@config.queues_string}]

            raise ArgumentError.new(err)
         end

         loader.create_task(queue:          queue,
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