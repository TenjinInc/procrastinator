module Procrastinator
   class Config
      attr_reader :queues, :log_level, :log_dir, :prefix, :test_mode, :context, :loader
      alias_method :test_mode?, :test_mode

      DEFAULT_LOG_DIRECTORY = 'log/'

      def initialize
         @test_mode        = false
         @queues           = []
         @loader           = nil
         @context          = nil
         @subprocess_block = nil
         @log_dir          = DEFAULT_LOG_DIRECTORY
         @log_level        = Logger::INFO
      end

      # Assigns a task loader
      # It should be called in an each_process block as well so that they get
      # distinct resources (eg. DB connections) from the parent process.
      def load_with(loader)
         @loader = loader

         raise MalformedTaskLoaderError.new('task loader cannot be nil') if @loader.nil?

         [:read_tasks, :create_task, :update_task, :delete_task].each do |method|
            unless @loader.respond_to? method
               raise MalformedTaskLoaderError.new("task loader #{@loader.class} must respond to ##{method}")
            end
         end
      end

      def provide_context(context)
         @context = context
      end

      # Accepts a block that will be executed on the queue sub-processes. Use it to control resource allocations.
      def each_process(&block)
         unless block
            err = '#provide_context must be given a block. That block will be run on each sub-process.'

            raise ArgumentError.new(err)
         end

         @subprocess_block = block
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

      # === everything below this isn't part of the setup DSL ===
      def validate!
         raise RuntimeError.new('setup block must call #load_with on the environment') if @loader.nil?
         raise RuntimeError.new('setup block must call #define_queue on the environment') if @queues.empty?

         if @context && !@queues.any? {|queue| queue.task_class.method_defined?(:context=)}
            err = <<~ERROR
               setup block called #provide_context, but no queue task classes import :context.

               Add this to your Task classes that expect to receive the context:

                  include Procrastinator::Task

                  task_attr :context
            ERROR

            raise RuntimeError.new(err)
         end
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

      def run_process_block
         @subprocess_block.call if @subprocess_block
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