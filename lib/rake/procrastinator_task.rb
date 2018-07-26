require 'rake'
require 'pathname'

namespace :procrastinator do
   desc 'Halt all Procrastinator processes'
   task :stop, [:pid_dir] do |task, args|
      pid_dir = args[:pid_dir] || Procrastinator::Config::DEFAULT_PID_DIRECTORY

      if !pid_dir.exist? || pid_dir.empty?
         raise <<~ERR
            Default PID directory does not exist or is empty. Run: 
               rake procrastinator:stop[directory]
            with the directory to search for pid files.
         ERR
      end

      pid_dir.each_child do |file|
         pid = file.read.to_i

         begin
            name = `ps -p #{pid} -o command`
            print "Halting worker process #{name} (pid: #{ pid })... "
            Process.kill('KILL', pid)
            puts 'halted'
         rescue Errno::ESRCH
            warn "Expected worker process pid=#{ pid }, but none was found. Continuing."
         end

         file.delete
      end

      puts '<= procrastinator:stop executed'
   end
end
