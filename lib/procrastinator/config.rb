module Procrastinator
   class Config
      attr_reader :queues, :log_level, :log_dir, :prefix, :test_mode
      alias_method :test_mode?, :test_mode

      DEFAULT_LOG_DIRECTORY = 'log/'

      def initialize
         @test_mode       = false
         @log_dir         = DEFAULT_LOG_DIRECTORY
         @log_level       = Logger::INFO
         @loader_factory  = nil
         @context_factory = nil
         @queues          = []
         @loader          = nil
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

         @queues << Queue.new(properties.merge(name: name, task_class: task_class))
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

      # === everything below thiss isn't part of the setup DSL ===
      def validate!
         raise RuntimeError.new('setup block must call #load_with on the environment') if @loader_factory.nil?
         raise RuntimeError.new('setup block must call #define_queue on the environment') if @queues.empty?

         if @context_factory && !@queues.any? {|queue| queue.task_class.method_defined?(:context=)}
            err = <<~ERROR
               setup block called #provide_context, but no queue task classes import :context.

               Add this to Task classes that expect to receive the context:

                  include Procrastinator::Task

                  import_task_data(:context)
            ERROR

            raise RuntimeError.new(err)
         end
      end

      def context
         @context_factory ? @context_factory.call : nil
      end

      # This is called to construct a new task loader for this env.
      # It should be called for each fork as well, with rebuild: true
      # so that they get distinct resources (eg. DB connections) from the parent process.
      def loader(rebuild: false)
         @loader = nil if rebuild

         @loader ||= create_loader
      end

      def queues_string
         # it drops the colon if you call #to_s on a symbol, so we need to add it back
         @queues.map {|queue| ":#{queue.name}"}.join(', ')
      end

      def single_queue?
         @queues.size == 1
      end

      def multiqueue?
         @queues.size > 1
      end

      def queue(name: nil)
         if name
            @queues.find do |q|
               q.name == name
            end
         else
            @queues.first
         end
      end

      private

      def create_loader
         loader = @loader_factory.call

         raise MalformedTaskLoaderError.new('task loader cannot be nil') if loader.nil?

         [:read_tasks, :create_task, :update_task, :delete_task].each do |method|
            unless loader.respond_to? method
               raise MalformedTaskLoaderError.new("task loader #{loader.class} must respond to ##{method}")
            end
         end

         loader
      end

      def verify_task_class(task_class)
         unless task_class.method_defined? :run
            raise MalformedTaskError.new("task #{task_class} does not support #run method")
         end

         # We're checking the interface compliance on init because it's one of those extremely rare cases where
         # you'd want to know early because the sub-processes would crash async, which is harder to debug.
         # It's a bit belt-and suspenders, but UX is important for devs, too. - robinetmiller
         if task_class.method_defined?(:run) && task_class.instance_method(:run).arity > 0
            err = "task #{task_class} cannot require parameters to its #run method"

            raise MalformedTaskError.new(err)
         end

         expected_arity = 1

         [:success, :fail, :final_fail].each do |method_name|
            if task_class.method_defined?(method_name) &&
                  task_class.instance_method(method_name).arity != expected_arity
               err = "task #{task_class} must accept #{expected_arity} parameter to its ##{method_name} method"

               raise MalformedTaskError.new(err)
            end
         end
      end
   end
end