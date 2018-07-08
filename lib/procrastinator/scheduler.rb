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

         loader.create(queue:          queue_name,
                       run_at:         run_at.to_i,
                       initial_run_at: run_at.to_i,
                       expire_at:      expire_at.nil? ? nil : expire_at.to_i,
                       data:           YAML.dump(data))
      end

      def reschedule(queue, identifier)
         UpdateProxy.new(@config, queue_name: queue, identifier: identifier)
      end

      class UpdateProxy
         def initialize(config, queue_name:, identifier:)
            identifier[:data] = YAML.dump(identifier[:data]) if identifier[:data]

            @config     = config
            @identifier = identifier
            @queue_name = queue_name
         end

         def to(run_at: nil, expire_at: nil)
            tasks = @config.loader.read(@identifier)

            if tasks.nil? || tasks.empty?
               raise RuntimeError.new "no task found matching #{@identifier}"
            elsif tasks.size > 1
               raise RuntimeError.new "too many (#{tasks.size}) tasks match #{@identifier}. Found: #{tasks}"
            end

            task = tasks.first

            new_data = {
                  attempts:      0,
                  last_error:    nil,
                  last_error_at: nil
            }

            if run_at.nil? && expire_at.nil?
               raise ArgumentError.new 'you must provide at least :run_at or :expire_at'
            elsif run_at
               if expire_at && run_at.to_i > expire_at.to_i
                  raise RuntimeError.new "given run_at (#{run_at}) is later than given expire_at (#{expire_at})"
               elsif task[:expire_at] && run_at.to_i > task[:expire_at]
                  raise RuntimeError.new "given run_at (#{run_at}) is later than saved expire_at (#{task[:expire_at]})"
               end
            end

            new_data = new_data.merge(run_at: run_at.to_i, initial_run_at: run_at.to_i) if run_at
            new_data = new_data.merge(expire_at: expire_at.to_i) if expire_at

            @config.loader.update(task[:id], new_data)
         end

         alias_method :at, :to
      end

      private

      # Scheduler must always get the loader indirectly. If it saves the loader to an instance variable,
      # then that could hold a reference to a bad (ie. gone) connection on the previous process
      def loader
         @config.loader
      end
   end
end