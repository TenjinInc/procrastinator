# frozen_string_literal: true

module Procrastinator
   class TaskContainer
      attr_accessor :context, :logger, :data, :procrastinator

      def initialize(context:, logger:, data:, env:)
         @context        = context
         @logger         = logger
         @data           = data
         @procrastinator = env
      end
   end
end
