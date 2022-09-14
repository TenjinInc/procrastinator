# frozen_string_literal: true

module Procrastinator
   module Test
      # Testing mock Task class
      #
      # You can use this like:
      #
      #    require 'procrastinator/rspec/mocks'
      #    # ...
      #    Procrastinator.config do |c|
      #       c.define_queue :test_queue, Procrastinator::RSpec::MockTask
      #    end
      #
      # @see MockDataTask for data-accepting tasks
      class MockTask
         attr_accessor :container, :logger, :scheduler

         def run
            @run = true
         end

         def run?
            @run
         end
      end

      # Data-accepting MockTask
      #
      # @see MockTask
      class MockDataTask < MockTask
         attr_accessor :data
      end
   end
end
