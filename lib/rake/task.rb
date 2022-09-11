# frozen_string_literal: true

require 'rake'

module Procrastinator
   # RakeTask builder. Provide this in your Rakefile:
   #
   #    require 'procrastinator/rake/task'
   #    Procrastinator::RakeTask.new do
   #       # return your Procrastinator::Scheduler here or construct it using Procrastinator.config
   #    end
   #
   class RakeTask
      def initialize
         define_rake_tasks(yield)
      end

      private

      def define_rake_tasks(scheduler)
         namespace :procrastinator do
            task :start, [:name, :pid_path] do |_, args|
               scheduler.daemonized!(args.name, args.pid_path)
            end

            task :stop, [:pid_path] do |_, args|
               pid = File.read(args.pid_path)

               Process.kill('TERM', pid)
            end
         end
      end
   end
end
