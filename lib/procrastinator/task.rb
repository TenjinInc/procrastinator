module Procrastinator
   module Task
      KNOWN_ATTRIBUTES = [:logger, :context, :data, :procrastinator]

      def self.included(base)
         base.extend(TaskClassMethods)
      end

      def method_missing(m, *args, &block)
         if KNOWN_ATTRIBUTES.include?(m)
            err = "To access Procrastinator::Task attribute :#{m}, call import_task_data(:#{m}) in your class definition."

            raise NameError.new(err)
         else
            super
         end
      end

      module TaskClassMethods

         def import_task_data(*fields)
            attr_list = KNOWN_ATTRIBUTES.collect {|a| ':' + a.to_s}.join(', ')

            fields.each do |field|
               err = "Unknown Procrastinator::Task attribute :#{field}. " +
                     "Importable attributes are: #{attr_list}"
               raise ArgumentError.new(err) unless KNOWN_ATTRIBUTES.include?(field)
            end

            attr_accessor *fields
         end
      end
   end
end