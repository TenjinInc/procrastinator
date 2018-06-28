module Procrastinator
   class Config
      attr_reader :queues, :log_level, :log_dir, :prefix, :test_mode
      alias_method :test_mode?, :test_mode

      DEFAULT_LOG_DIRECTORY = 'log/'

      def initialize
         @test_mode       = false
         @queues          = {}
         @log_dir         = DEFAULT_LOG_DIRECTORY
         @log_level       = Logger::INFO
         @loader_factory  = nil
         @context_factory = Proc.new {}
      end

      # Accepts a block that will be executed on the queue sub process. This is done to separate resource allocations
      # like database connections.
      # The result will be used to load tasks
      def load_with(&block)
         unless block
            raise RuntimeError.new('#load_with must be given a block that produces a persistence handler for tasks')
         end

         @loader_factory = block
      end

      # Accepts a block that will be executed on the queue sub process.
      # The result will be passed into the task methods.
      def provide_context(&block)
         unless block
            err = '#provide_context must be given a block that returns a value to be passed to your task event hooks'

            raise RuntimeError.new(err)
         end

         @context_factory = block
      end

      def define_queue(name, task_class, properties = {})
         raise ArgumentError.new('queue name cannot be nil') if name.nil?
         raise ArgumentError.new('queue task class cannot be nil') if task_class.nil?

         verify_task_class(task_class)

         @queues[name] = properties.merge(task_class: task_class)
      end

      def enable_test_mode
         @test_mode = true
      end

      def log_in(path)
         @log_dir = path
      end

      def log_at_level(lvl)
         @log_level = lvl
      end

      def prefix_processes(prefix)
         @prefix = prefix
      end

      def verify
         raise RuntimeError.new('setup block must call #load_with on the environment') if @loader_factory.nil?
         raise RuntimeError.new('setup block must call #define_queue on the environment') if @queues.empty?
      end

      def context
         @context_factory.call
      end

      # This is called to construct a new task loader for this env.
      # It should be called for each fork as well,
      # so that they get distinct resources (eg. DB connections) from the parent process.
      def loader
         loader = @loader_factory.call

         raise MalformedTaskLoaderError.new('task loader cannot be nil') if loader.nil?

         [:read_tasks, :create_task, :update_task, :delete_task].each do |method|
            unless loader.respond_to? method
               raise MalformedTaskLoaderError.new("task loader #{loader.class} must respond to ##{method}")
            end
         end

         loader
      end

      def queues_string
         # it drops the colon if you call #to_s on a symbol, so we need to add it back
         @queues.keys.map {|key| ":#{key}"}.join(', ')
      end

      def many_queues?
         queues.size > 1
      end

      private

      def verify_task_class(task_class)
         unless task_class.method_defined? :run
            raise MalformedTaskError.new("task #{task_class} does not support #run method")
         end

         # We're checking these on init because it's one of those extremely rare cases where you'd want to know early
         # because of the sub-processes. It's a bit belt-and suspenders, but UX is important for         # devs, too.
         expected_arity = {run: 2, success: 3, fail: 3, final_fail: 3}
         expected_arity.each do |method_name, arity|
            if task_class.method_defined?(method_name) && task_class.instance_method(method_name).arity < arity
               err = "task #{task_class} must accept #{arity} parameters to its ##{method_name} method"

               raise MalformedTaskError.new(err)
            end
         end
      end
   end
end