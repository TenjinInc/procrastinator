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
         def self.define(**args, &block)
            new.define(**args, &block)
         end

         # Defines procrastinator:start and procrastinator:stop Rake tasks that operate on the given scheduler.
         # If provided a block, that block will run in the daemon process.
         #
         # @param pid_path [Pathname, File, String, nil]
         # @yieldreturn scheduler [Procrastinator::Scheduler]
         def define(pid_path: nil)
            raise ArgumentError, 'must provide a scheduler builder block' unless block_given?

            @pid_path = Scheduler::DaemonWorking.normalize_pid pid_path

            namespace :procrastinator do
               desc 'Start the Procrastinator daemon'
               task :start do
                  start(yield)
               end

               desc 'Show Procrastinator daemon status'
               task :status do
                  status
               end

               desc 'Stop the Procrastinator daemon'
               task :stop do
                  stop
               end

               desc 'Restart Procrastinator daemon'
               task restart: [:stop, :start]
            end
         end

         private

         def start(scheduler)
            scheduler.work.daemonized!(@pid_path)
            # ::Rake::Task['procrastinator:after_daemon'].invoke
            # scheduler.work.threaded
         end

         def status
            if Scheduler::DaemonWorking.running?(@pid_path)
               warn "Procrastinator instance running (pid #{ File.read(@pid_path) })"
            else
               warn "No Procrastinator instance detected for #{ @pid_path }"
            end
         end

         def stop
            Scheduler::DaemonWorking.halt!(@pid_path)
         end
      end
   end
end
