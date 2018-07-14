# frozen_string_literal: true

module Procrastinator
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
            err = "To access Procrastinator::Task attribute :#{ method_name }, " \
                  "call task_attr(:#{ method_name }) in your class definition."

            raise NameError, err
         end

         super
      end

      module TaskClassMethods
         def task_attr(*fields)
            attr_list = KNOWN_ATTRIBUTES.collect { |a| ':' + a.to_s }.join(', ')

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
