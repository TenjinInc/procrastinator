# frozen_string_literal: true

module Procrastinator
   class Config
      attr_reader :queues, :log_level, :prefix, :test_mode, :context, :loader, :pid_dir
      alias test_mode? test_mode

      DEFAULT_LOG_DIRECTORY = 'log/'
      DEFAULT_PID_DIRECTORY = 'pid/'

      def initialize
         @test_mode        = false
         @queues           = []
         @loader           = nil
         @context          = nil
         @subprocess_block = nil
         @log_dir          = Pathname.new(DEFAULT_LOG_DIRECTORY)
         @log_level        = Logger::INFO
         @pid_dir          = Pathname.new(DEFAULT_PID_DIRECTORY)
      end

      module DSL
         # Assigns a task loader
         # It should be called in an each_process block as well so that they get
         # distinct resources (eg. DB connections) from the parent process.
         def load_with(loader)
            if loader.is_a? Hash
               unless loader.key? :location
                  raise ArgumentError, 'Must pass keyword :location if specifying a location for CSV file'
               end

               loader = Loader::CSVLoader.new(loader[:location])
            end

            raise MalformedTaskLoaderError, 'task loader cannot be nil' if loader.nil?

            [:read, :create, :update, :delete].each do |method|
               unless loader.respond_to? method
                  raise MalformedTaskLoaderError, "task loader #{ loader.class } must respond to ##{ method }"
               end
            end

            @loader = loader
         end

         def provide_context(context)
            @context = context
         end

         # Accepts a block that will be executed on the queue sub-processes. Use it to control resource allocations.
         def each_process(prefix: nil, pid_dir: DEFAULT_PID_DIRECTORY, &block)
            @prefix           = prefix
            @subprocess_block = block
            @pid_dir          = Pathname.new(pid_dir)
         end

         def define_queue(name, task_class, properties = {})
            raise ArgumentError, 'queue name cannot be nil' if name.nil?
            raise ArgumentError, 'queue task class cannot be nil' if task_class.nil?

            verify_task_class(task_class)

            @queues << Queue.new(properties.merge(name: name, task_class: task_class))
         end

         def enable_test_mode
            @test_mode = true
         end

         def log_inside(path)
            @log_dir = path ? Pathname.new(path) : path
         end

         def log_at_level(lvl)
            @log_level = lvl
         end
      end

      include DSL

      def setup(test_mode = false)
         yield(self)

         enable_test_mode if test_mode

         load_with(Loader::CSVLoader.new) unless @loader

         raise 'setup block must call #define_queue on the environment' if @queues.empty?

         if @context && @queues.none? { |queue| queue.task_class.method_defined?(:context=) }
            raise <<~ERROR
               setup block called #provide_context, but no queue task classes import :context.

               Add this to your Task classes that expect to receive the context:

                  include Procrastinator::Task

                  task_attr :context
            ERROR
         end

         self
      end

      def log_dir
         @test_mode ? false : @log_dir
      end

      def queues_string
         # it drops the colon if you call #to_s on a symbol, so we need to add it back
         @queues.map { |queue| ":#{ queue.name }" }.join(', ')
      end

      def single_queue?
         @queues.size == 1
      end

      def run_process_block
         @subprocess_block&.call
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
            raise MalformedTaskError, "task #{ task_class } does not support #run method"
         end

         # We're checking the interface compliance on init because it's one of those extremely rare cases where
         # you'd want to know early because the sub-processes would crash async, which is harder to debug.
         # It's a bit belt-and suspenders, but UX is important for devs, too. - robinetmiller
         if task_class.method_defined?(:run) && task_class.instance_method(:run).arity.positive?
            err = "task #{ task_class } cannot require parameters to its #run method"

            raise MalformedTaskError, err
         end

         expected_arity = 1

         [:success, :fail, :final_fail].each do |method_name|
            next unless task_class.method_defined?(method_name)
            next if task_class.instance_method(method_name).arity == expected_arity

            err = "task #{ task_class } must accept #{ expected_arity } parameter to its ##{ method_name } method"

            raise MalformedTaskError, err
         end
      end
   end

   class MalformedTaskLoaderError < StandardError
   end
end
