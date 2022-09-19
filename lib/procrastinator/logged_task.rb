# frozen_string_literal: true

require 'json'
require 'ostruct'
require 'timeout'
# require 'forwardable'
require 'delegate'
require_relative 'task'

module Procrastinator
   # Task wrapper that adds logging to each step.
   #
   # @author Robin Miller
   #
   # @see Task
   class LoggedTask < DelegateClass(Task)
      attr_reader :logger

      alias task __getobj__

      def initialize(task, logger: Logger.new(StringIO.new))
         super task
         @logger = logger || raise(ArgumentError, 'Logger cannot be nil')
      end

      # (see Task#run)
      def run
         task.run

         begin
            @logger.info("Task completed: #{ task }")
         rescue StandardError => e
            warn "Task logging error: #{ e.message }"
         end
      end

      # @param (see Task#fail)
      def fail(error)
         hook = task.fail(error)
         begin
            @logger.error("Task #{ hook }ed: #{ task }")
         rescue StandardError => e
            warn "Task logging error: #{ e.message }"
         end
         hook
      end
   end
end
