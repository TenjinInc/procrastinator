# frozen_string_literal: true

require 'rake'

module Procrastinator
   # RakeTask builder. Provide this in your Rakefile:
   #
   #    require 'procrastinator/rake/task'
   #    Procrastinator::RakeTask.new('/var/run') do
   #       # return your Procrastinator::Scheduler here or construct it using Procrastinator.config
   #    end
   #
   class RakeTask
      def initialize(pid_path = nil)
         @pid_path = pid_path
         define_rake_tasks(yield)
      end

      private

      def define_rake_tasks(scheduler)
         namespace :procrastinator do
            task :start, [:pid_path] do |_, args|
               args.with_defaults pid_path: @pid_path
               scheduler.daemonized!(args.pid_path)
            end

            task :stop, [:pid_path] do |_, args|
               args.with_defaults pid_path: @pid_path
               pid = DaemonWorking.normalize_pid(args.pid_path).read

               Process.kill('TERM', pid)
            end
         end
      end
   end
end
