# frozen_string_literal: true

module Procrastinator
   class Scheduler
      def initialize(config)
         @config = config
      end

      def delay(queue = nil, data: nil, run_at: Time.now.to_i, expire_at: nil)
         verify_queue_arg!(queue)

         queue = @config.queue.name if @config.single_queue?

         verify_queue_data!(queue, data)

         loader.create(queue:          queue,
                       run_at:         run_at.to_i,
                       initial_run_at: run_at.to_i,
                       expire_at:      expire_at.nil? ? nil : expire_at.to_i,
                       data:           YAML.dump(data))
      end

      def reschedule(queue, identifier)
         UpdateProxy.new(@config, queue_name: queue, identifier: identifier)
      end

      def cancel(queue, identifier)
         tasks = loader.read(identifier.merge(queue: queue))

         raise "no task matches search: #{ identifier }" if tasks.empty?
         raise "multiple tasks match search: #{ identifier }" if tasks.size > 1

         loader.delete(tasks.first[:id])
      end

      class UpdateProxy
         def initialize(config, queue_name:, identifier:)
            identifier[:data] = YAML.dump(identifier[:data]) if identifier[:data]

            @config     = config
            @identifier = identifier
            @queue_name = queue_name
         end

         def to(run_at: nil, expire_at: nil)
            task = fetch_task

            verify_time_provided(run_at, expire_at)
            validate_run_at(run_at, task[:expire_at], expire_at)

            new_data = {
                  attempts:      0,
                  last_error:    nil,
                  last_error_at: nil
            }

            new_data = new_data.merge(run_at: run_at.to_i, initial_run_at: run_at.to_i) if run_at
            new_data = new_data.merge(expire_at: expire_at.to_i) if expire_at

            @config.loader.update(task[:id], new_data)
         end

         alias at to

         private

         def verify_time_provided(run_at, expire_at)
            raise ArgumentError, 'you must provide at least :run_at or :expire_at' if run_at.nil? && expire_at.nil?
         end

         def validate_run_at(run_at, saved_expire_at, expire_at)
            return unless run_at

            after_new_expire = expire_at && run_at.to_i > expire_at.to_i

            raise "given run_at (#{ run_at }) is later than given expire_at (#{ expire_at })" if after_new_expire

            after_old_expire = saved_expire_at && run_at.to_i > saved_expire_at

            raise "given run_at (#{ run_at }) is later than saved expire_at (#{ saved_expire_at })" if after_old_expire
         end

         def fetch_task
            tasks = @config.loader.read(@identifier)

            raise "no task found matching #{ @identifier }" if tasks.nil? || tasks.empty?
            raise "too many (#{ tasks.size }) tasks match #{ @identifier }. Found: #{ tasks }" if tasks.size > 1

            tasks.first
         end
      end

      private

      # Scheduler must always get the loader indirectly. If it saves the loader to an instance variable,
      # then that could hold a reference to a bad (ie. gone) connection on the previous process
      def loader
         @config.loader
      end

      def verify_queue_arg!(queue_name)
         return if !queue_name.nil? || @config.single_queue?

         queue_list = @config.queues_string
         err        = "queue must be specified when more than one is registered. Defined queues are: #{ queue_list }"

         raise ArgumentError, err
      end

      def verify_queue_data!(queue_name, data)
         queue = @config.queue(name: queue_name)

         unless queue
            queue_list = @config.queues_string
            raise ArgumentError, "there is no :#{ queue_name } queue registered. Defined queues are: #{ queue_list }"
         end

         if data.nil?
            if queue.task_class.method_defined?(:data=)
               raise ArgumentError, "task #{ queue.task_class } expects to receive :data. Provide :data to #delay."
            end
         elsif !queue.task_class.method_defined?(:data=)
            raise ArgumentError, <<~ERROR
               task #{ queue.task_class } does not import :data. Add this in your class definition:
                     import_test_data :data
            ERROR
         end
      end
   end
end
