# frozen_string_literal: true

require 'rake'

module Procrastinator
   module Rake
      # RakeTask builder. Provide this in your Rakefile:
      #
      #    require 'procrastinator/rake/task'
      #    Procrastinator::RakeTask.new('/var/run') do
      #       # return your Procrastinator::Scheduler here or construct it using Procrastinator.config
      #    end
      #
      class DaemonTasks
         include ::Rake::Cloneable
         include ::Rake::DSL

         # Shorthand for DaemonTasks.new.define
         #
         # @param (see #define)
         # @see DaemonTasks#define
         def self.define(*args)
            new.define(*args)
         end

         # Defines procrastinator:start and procrastinator:stop Rake tasks that operate on the given scheduler.
         # If provided a block, that block will run in the daemon process.
         #
         # @param scheduler [Procrastinator::Scheduler]
         # @param pid_path [Pathname, File, String, nil]
         def define(scheduler:, pid_path: nil, &block)
            namespace :procrastinator do
               task :start do
                  scheduler.work.daemonized!(pid_path, &block)
               end

               task :stop do
                  Process.kill('TERM', File.read(pid_path).to_i)
               end
            end
         end
      end
   end
end
