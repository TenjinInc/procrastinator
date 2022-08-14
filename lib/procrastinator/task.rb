# frozen_string_literal: true

module Procrastinator
   # Module to be included by user-defined task classes. It provides some extra error checking and a convenient way
   # for the task class to access additional information (data, logger, etc) from Procrastinator.
   #
   # If you are averse to including this in your task class, you can just declare an attr_accessor for the
   # information you want Procrastinator to feed your task.
   #
   # @author Robin Miller
   module Task
      KNOWN_ATTRIBUTES = [:logger, :context, :data, :scheduler].freeze

      def self.included(base)
         base.extend(TaskClassMethods)
      end

      def respond_to_missing?(name, include_private)
         super
      end

      def method_missing(method_name, *args, &block)
         if KNOWN_ATTRIBUTES.include?(method_name)
            raise NameError, "To access Procrastinator::Task attribute :#{ method_name }, " \
                             "call task_attr(:#{ method_name }) in your class definition."
         end

         super
      end

      # Module that provides the task_attr class method for task definitions to declare their expected information.
      module TaskClassMethods
         def task_attr(*fields)
            attr_list = KNOWN_ATTRIBUTES.collect { |a| ":#{ a }" }.join(', ')

            fields.each do |field|
               err = "Unknown Procrastinator::Task attribute :#{ field }. " \
                     "Importable attributes are: #{ attr_list }"
               raise ArgumentError, err unless KNOWN_ATTRIBUTES.include?(field)
            end

            attr_accessor(*fields)
         end
      end
   end
end
