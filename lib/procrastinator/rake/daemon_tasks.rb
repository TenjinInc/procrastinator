# frozen_string_literal: true

require 'rake'

module Procrastinator
   # Rake tasks specific to Procrastinator.
   #
   # Provide this in your Rakefile:
   #
   #    require 'procrastinator/rake/task'
   #    Procrastinator::RakeTask.new do
   #       # return your Procrastinator::Scheduler here or construct it using Procrastinator.config
   #    end
   #
   # And then you will be able to run rake tasks like:
   #
   #    bundle exec rake procrastinator:start
   module Rake
      # RakeTask builder class. Use DaemonTasks.define to generate the needed tasks.
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
         #
         # @param pid_path [Pathname, File, String, nil] The pid file path
         # @yieldreturn [Procrastinator::Scheduler] Constructed Scheduler to use as basis for starting tasks
         #
         # @see Scheduler::DaemonWorking#daemonized!
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
               task stop: [:status] do
                  stop
               end

               desc 'Restart Procrastinator daemon'
               task restart: [:stop, :start]
            end
         end

         private

         def start(scheduler)
            warn 'Starting Procrastinator'
            scheduler.work.daemonized!(@pid_path)
         end

         def status
            warn "Checking #{ @pid_path }..."
            msg = if Scheduler::DaemonWorking.running?(@pid_path)
                     "Procrastinator pid #{ File.read(@pid_path) } instance running."
                  elsif File.exist?(@pid_path)
                     "Procrastinator pid #{ File.read(@pid_path) } is not running. Maybe it crashed?"
                  else
                     "Procrastinator is not running (No such file - #{ @pid_path })"
                  end

            warn msg
         end

         def stop
            return unless Scheduler::DaemonWorking.running?(@pid_path)

            pid = File.read(@pid_path)
            Scheduler::DaemonWorking.halt!(@pid_path)
            warn "Procrastinator pid #{ pid } halted."
         end
      end
   end
end
