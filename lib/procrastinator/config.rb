# frozen_string_literal: true

module Procrastinator
   # Configuration object (State Pattern) used to coordinate settings across
   # various components within Procrastinator.
   #
   # All of its state is read-only, set using the methods in the DSL module below.
   #
   # @author Robin Miller
   #
   # @!attribute [r] :queues
   #    @return [Array] List of defined queues
   # @!attribute [r] :context
   #    @return [Object] Provided context object that will be forwarded to tasks
   # @!attribute [r] :loader
   #    @return [Object] Provided persistence strategy object to use for task I/O
   # @!attribute [r] :log_dir
   #    @return [Pathname] Directory to write log files in
   # @!attribute [r] :log_level
   #    @return [Integer] Logging level to use
   # @!attribute [r] :log_shift_age
   #    @return [Integer] Number of previous files to keep (see Ruby Logger for details)
   # @!attribute [r] :log_shift_size
   #    @return [Integer] Filesize before rotating to a new logfile (see Ruby Logger for details)
   class Config
      attr_reader :queues, :log_dir, :log_level, :log_shift_age, :log_shift_size, :context, :loader

      DEFAULT_LOG_DIRECTORY = Pathname.new('log/').freeze
      DEFAULT_LOG_SHIFT_AGE = 0

      # TODO: This cop for ** is currently incorrect. This disable can be removed once they fix it.
      # rubocop:disable Layout/SpaceAroundOperators
      DEFAULT_LOG_SHIFT_SIZE = 2 ** 20 # 1 MB
      # rubocop:enable Layout/SpaceAroundOperators

      def initialize
         @queues         = []
         @loader         = nil
         @context        = nil
         @log_dir        = DEFAULT_LOG_DIRECTORY
         @log_level      = Logger::INFO
         @log_shift_age  = DEFAULT_LOG_SHIFT_AGE
         @log_shift_size = DEFAULT_LOG_SHIFT_SIZE
      end

      # Collection of all of the methods intended for use within Procrastinator.setup
      #
      # @see Procrastinator
      module DSL
         # Assigns a task loader
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

         def define_queue(name, task_class, properties = {})
            raise ArgumentError, 'queue name cannot be nil' if name.nil?
            raise ArgumentError, 'queue task class cannot be nil' if task_class.nil?

            verify_task_class(task_class)

            @queues << Queue.new(properties.merge(name: name, task_class: task_class))
         end

         # Sets details of logging behaviour
         #
         # @param directory [Pathname,String] the directory to save logs within.
         # @param level [Logger::UNKNOWN,Logger::FATAL,Logger::ERROR,Logger::WARN,Logger::INFO,Logger::DEBUG,Integer,Boolean] the Ruby Logger level to use. If falsey, no logging is performed.
         # @param shift_age [Integer] number of old log files to keep (see Ruby Logger for details)
         # @param shift_size [Integer] filesize before log is rotated to a fresh file (see Ruby Logger for details)
         def log_with(directory: @log_dir, level: @log_level, shift_age: @log_shift_age, shift_size: @log_shift_size)
            @log_dir        = directory ? Pathname.new(directory) : directory
            @log_level      = level
            @log_shift_age  = shift_age
            @log_shift_size = shift_size
         end
      end

      include DSL

      def setup
         yield(self)

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

      def queues_string
         # it drops the colon if you call #to_s on a symbol, so we need to add it back
         @queues.map { |queue| ":#{ queue.name }" }.join(', ')
      end

      def single_queue?
         @queues.size == 1
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

         # Checking the interface compliance on init because it's one of those rare cases where you'd want to know early
         # Otherwise, you wouldn't know until task execution, which could be far in the future.
         # Always nice to catch errors when you can predict them because UX is important for devs, too. - retm
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
