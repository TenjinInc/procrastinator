require 'spec_helper'

module Procrastinator
   describe QueueManager do
      let(:test_task) { Test::Task::AllHooks }

      describe '#initialize' do
         include FakeFS::SpecHelpers

         let(:config) { Config.new }

         before(:each) do
            FileUtils.rm_rf('/*') if FakeFS.activated?
         end

         it 'should start a log file for the main process' do
            QueueManager.new(config)

            expect(File).to exist(config.log_dir + 'queue-manager.log')
         end

         it 'should put the log file in the log directory' do
            %w[/var/log/myapp
               another/log/place].each do |dir|
               config.log_inside dir

               QueueManager.new(config)

               expect(File).to exist(dir)
               expect(File).to exist("#{dir}/queue-manager.log")
            end
         end

         it 'should NOT start a log file if logging is disabled' do
            config.log_inside false

            QueueManager.new(config)

            expect(File).to_not exist(Config::DEFAULT_LOG_DIRECTORY)
            expect(File).to_not exist("#{Config::DEFAULT_LOG_DIRECTORY}/queue-manager.log")
         end

         it 'should log at the given level' do
            logger = double('log')

            allow(Logger).to receive(:new).and_return(logger)

            config.log_at_level Logger::FATAL

            expect(logger).to receive(:level=).with(Logger::FATAL)

            QueueManager.new(config)
         end
      end

      describe '#spawn_workers' do
         include FakeFS::SpecHelpers

         let(:persister) { Test::Persister.new }
         let(:config) do
            config = Config.new
            config.load_with(persister)
            config
         end

         let(:manager) { QueueManager.new(config) }

         it 'should create a worker for each queue definition' do
            queue_defs = [:test2a, :test2b, :test2c]
            queue_defs.each do |name|
               config.define_queue(name, test_task)
            end

            expect(manager).to receive(:spawn_worker).with(config.queues[0], hash_including(:scheduler))
            expect(manager).to receive(:spawn_worker).with(config.queues[1], hash_including(:scheduler))
            expect(manager).to receive(:spawn_worker).with(config.queues[2], hash_including(:scheduler))

            manager.spawn_workers
         end

         it 'should pass in the scheduler' do
            config.define_queue(:test2a, test_task)

            expect(manager).to receive(:spawn_worker).with(anything, hash_including(scheduler: instance_of(Scheduler)))

            manager.spawn_workers
         end

         it 'should return the scheduler it made' do
            scheduler = double('s')

            expect(Scheduler).to receive(:new).with(config, manager).and_return(scheduler)

            allow(manager).to receive(:fork)

            expect(manager.spawn_workers).to be scheduler
         end

         it 'should NOT spawn workers when ENV variable PROCRASTINATOR_STOP is enabled' do
            old_stop = ENV['PROCRASTINATOR_STOP']

            ENV['PROCRASTINATOR_STOP'] = 'true'

            queue_defs = [:test2a, :test2b, :test2c]
            queue_defs.each do |name|
               config.define_queue(name, test_task)
            end

            expect(manager).to_not receive(:spawn_worker)
            expect(manager).to_not receive(:fork)

            manager.spawn_workers

            ENV['PROCRASTINATOR_STOP'] = old_stop
         end

         it 'should still remove old processes when ENV variable PROCRASTINATOR_STOP is enabled' do
            old_stop = ENV['PROCRASTINATOR_STOP']

            ENV['PROCRASTINATOR_STOP'] = 'true'

            FileUtils.mkpath 'pid/'
            File.open('pid/test1-queue-worker.pid', 'w') { |f| f.print 144 }

            allow(manager).to receive(:fork) # stub

            expect(Process).to receive(:kill)

            manager.spawn_workers

            ENV['PROCRASTINATOR_STOP'] = old_stop
         end

         it 'should log that it cannot spawn queues when ENV variable PROCRASTINATOR_STOP is enabled' do
            old_stop = ENV['PROCRASTINATOR_STOP']

            ENV['PROCRASTINATOR_STOP'] = 'true'

            config.define_queue(:test2a, test_task)
            config.define_queue(:test2b, test_task)
            config.define_queue(:test2c, test_task)

            allow(manager).to receive(:fork).and_return 1 # stub fork

            manager.spawn_workers

            log = File.read('log/queue-manager.log')

            msg = 'Cannot spawn queue workers because environment variable PROCRASTINATOR_STOP is set'

            expect(log).to include(msg)

            ENV['PROCRASTINATOR_STOP'] = old_stop
         end

         it 'should kill all PIDs found in the files before forking' do
            pid1 = 1192
            pid2 = 12907

            FileUtils.mkpath 'pid/'
            File.open('pid/test1-queue-worker.pid', 'w') { |f| f.print pid1 }
            File.open('pid/test2-queue-worker.pid', 'w') { |f| f.print pid2 }

            expect(manager).to_not receive(:fork)
            expect(Process).to receive(:kill).with('KILL', pid1)
            expect(Process).to receive(:kill).with('KILL', pid2)

            manager.spawn_workers
         end

         it 'should delete the pid files for the killed processes' do
            pid1 = 1192
            pid2 = 12907

            dir = 'pid/'

            FileUtils.mkpath 'pid/'
            File.open('pid/test1-queue-worker.pid', 'w') { |f| f.print pid1 }
            File.open('pid/test2-queue-worker.pid', 'w') { |f| f.print pid2 }

            expect(manager).to_not receive(:fork)
            allow(Process).to receive(:kill)

            manager.spawn_workers

            expect(Pathname.new(dir)).to be_empty
         end

         it 'should log all killed PIDs' do
            pid1 = 5411
            pid2 = 13134

            FileUtils.mkpath 'pid/'
            File.open('pid/test1-queue-worker.pid', 'w') { |f| f.print pid1 }
            File.open('pid/test2-queue-worker.pid', 'w') { |f| f.print pid2 }

            expect(manager).to_not receive(:fork) # sanity/protection
            allow(Process).to receive(:kill)

            manager.spawn_workers

            log = File.read('log/queue-manager.log')

            expect(log).to include("Killing old worker process pid: #{pid1}")
            expect(log).to include("Killing old worker process pid: #{pid2}")
         end

         it 'should ignore missing PIDs' do
            missing_pid = 5411
            old_pid     = 12314

            FileUtils.mkpath 'pid/'
            File.open('pid/test1-queue-worker.pid', 'w') { |f| f.print missing_pid }
            File.open('pid/test2-queue-worker.pid', 'w') { |f| f.print old_pid }

            expect(manager).to_not receive(:fork) # sanity/protection
            raised = false
            expect(Process).to receive(:kill).twice do
               if raised
                  old_pid
               else
                  raise Errno::ESRCH
                  raised = true
               end
            end

            manager.spawn_workers
         end

         it 'should log missing PIDs' do
            pid = 5411

            FileUtils.mkpath 'pid/'
            File.open('pid/test1-queue-worker.pid', 'w') { |f| f.print pid }

            expect(manager).to_not receive(:fork) # sanity/protection
            allow(Process).to receive(:kill).and_raise Errno::ESRCH

            manager.spawn_workers

            log = File.read('log/queue-manager.log')

            expect(log).to include("Expected old worker process pid=#{pid}, but none was found")
         end
      end

      describe '#spawn_worker' do
         include FakeFS::SpecHelpers

         let(:persister) { Test::Persister.new }
         let(:config) do
            config = Config.new
            config.load_with(persister)
            config
         end

         let(:manager) { QueueManager.new(config) }

         before(:each) do
            FileUtils.rm_rf('/*') if FakeFS.activated?
         end

         context 'test mode' do
            let(:queue) { Procrastinator::Queue.new(name: :test_queue, task_class: test_task) }

            before(:each) do
               config.enable_test_mode
            end

            it 'should create a worker the queue' do
               config.define_queue(:test_queue, test_task)

               expect(QueueWorker).to receive(:new)
                                            .with(satisfy do |arg|
                                               arg[:queue].name == :test_queue && arg[:queue].task_class == test_task
                                            end)
                                            .and_return(double('worker', work: nil))

               manager.spawn_worker(queue)
            end

            it 'should provide the queue' do
               config.define_queue(:test2a, test_task)

               expect(QueueWorker).to receive(:new)
                                            .with(hash_including(queue: queue))
                                            .and_return(double('worker', work: nil))

               manager.spawn_worker(queue)
            end

            it 'should provide the scheduler' do
               scheduler = double('scheduler')

               config.define_queue(:test2a, test_task)

               expect(QueueWorker).to receive(:new)
                                            .with(hash_including(scheduler: scheduler))
                                            .and_return(double('worker', work: nil))

               manager.spawn_worker(queue, scheduler: scheduler)
            end

            it 'should provide the config instance' do
               config.define_queue(:test_queue, test_task)

               expect(QueueWorker).to receive(:new)
                                            .with(hash_including(config: config))
                                            .and_return(double('worker', work: nil))

               manager.spawn_worker(config.queues.first)
            end

            it 'should NOT fork' do
               config.define_queue(:test, test_task)

               expect(manager).to_not receive(:fork)

               manager.spawn_worker(queue)
            end

            it 'should NOT call #work' do
               config.define_queue(:test, test_task)

               expect_any_instance_of(QueueWorker).to_not receive(:work)

               manager.spawn_worker(queue)
            end

            it 'should NOT change the process title' do
               config.define_queue(:test, test_task)

               expect(Process).to_not receive(:setproctitle)

               manager.spawn_worker(queue)
            end

            it 'should NOT open a log file' do
               queue_name = :queue1

               config.define_queue(queue_name, test_task)

               FakeFS do
                  manager.spawn_worker(queue)

                  expect(File.file?("log/#{queue_name}-queue-worker.log")).to be false
               end
            end

            it 'should pass the config to the worker' do
               config.load_with double('specific persister', read: nil, create: nil, update: nil, delete: nil)

               config.define_queue(:test, test_task)

               expect(QueueWorker).to receive(:new).with(hash_including(config: config)).and_call_original

               manager.spawn_worker(queue)
            end
         end

         context 'live mode' do
            context 'parent process' do
               include FakeFS::SpecHelpers

               before(:each) do
                  allow(Process).to receive(:detach)
                  allow(manager).to receive(:fork).and_return(1)
                  allow(manager).to receive(:`).and_return('')
               end

               let(:queue) { Procrastinator::Queue.new(name: :test_queue, task_class: test_task) }

               it 'should fork a worker process' do
                  expect(manager).to receive(:fork).once.and_return(double('a child pid'))

                  manager.spawn_worker(queue)
               end

               it 'should warn if the worker name is identical to another process on the system' do
                  name = 'reminders-queue-worker'

                  queue = Procrastinator::Queue.new(name: :reminders, task_class: test_task)

                  err = <<~WARNING
                     Warning: there is another process named "#{name}". Use #each_process(prefix: '') in
                              Procrastinator setup if you want to help yourself distinguish them.
                  WARNING

                  expect(manager).to receive(:`).with("pgrep -f #{name}").and_return("13412")

                  expect do
                     manager.spawn_worker(queue)
                  end.to output(err).to_stderr
               end

               it 'should NOT warn if the worker name is unique' do
                  config.define_queue(:reminders, test_task)

                  allow(manager).to receive(:`).and_return('')

                  expect do
                     manager.spawn_worker(queue)
                  end.to_not output.to_stderr
               end

               it 'should NOT wait for the QueueWorker' do
                  queue = Procrastinator::Queue.new(name: :waiting_queue, task_class: test_task)

                  Timeout::timeout(1) do
                     pid = double('pid')

                     allow(manager).to receive(:fork).and_return(pid)

                     expect(Process).to receive(:detach).with(pid)

                     manager.spawn_worker(queue)
                  end
               end

               it 'should store the PID of children in the manager' do
                  worker = double('queue worker 3', long_name: 'work3')

                  allow(manager).to receive(:fork).and_return(1337)
                  allow(QueueWorker).to receive(:new).and_return worker

                  manager.spawn_worker(queue)

                  expect(manager.workers).to eq(worker => 1337)
               end

               it 'should write a PID file for each child within the pid directory' do
                  config.each_process prefix: 'myapp'

                  queue = Procrastinator::Queue.new(name: :reminder, task_class: test_task)

                  pid = 1234

                  allow(manager).to receive(:fork).and_return(pid)

                  manager.spawn_worker(queue)

                  expect(File).to exist('pid/myapp-reminder-queue-worker.pid')
               end

               it 'should write PID files in the given directory' do
                  %w[/var/pid
                     some/pid/place].each do |dir|

                     config.each_process pid_dir: dir

                     config.define_queue(:test1, test_task)

                     pid = 18

                     allow(manager).to receive(:fork).and_return(pid)

                     manager.spawn_worker(queue)

                     expect(File).to exist("#{dir}/test_queue-queue-worker.pid")
                  end
               end

               it 'should store the child PID in that queue pid file' do
                  config.define_queue(:test1, test_task)
                  config.define_queue(:test2, test_task)

                  pid = 15845

                  allow(manager).to receive(:fork).and_return(pid)

                  manager.spawn_worker(queue)

                  queue_file = File.read('pid/test_queue-queue-worker.pid')

                  expect(queue_file).to eq pid.to_s
               end

               it 'should NOT run the each_process hook' do
                  run = false

                  config.each_process do
                     run = true
                  end

                  config.define_queue(:test_queue, test_task)

                  expect(config).to_not receive(:subprocess_block)
                  expect(run).to be false

                  manager.spawn_worker(config.queues.first)
               end
            end

            context 'subprocess' do
               let(:queue) { Procrastinator::Queue.new(name: :test_queue, task_class: test_task) }

               let(:worker) { double('worker',
                                     work:      nil,
                                     start_log: nil,
                                     long_name: 'test-worker') }

               before(:each) do
                  allow(Process).to receive(:setproctitle)
                  allow(manager).to receive(:fork).and_return(nil)
                  allow_any_instance_of(QueueManager).to receive(:shutdown_worker)
               end

               it 'should create a QueueWorker' do
                  config.define_queue(:test_queue, test_task)

                  expect(QueueWorker).to receive(:new)
                                               .once
                                               .and_return(double('worker',
                                                                  work:      nil,
                                                                  start_log: nil,
                                                                  long_name: 'test-worker'))
                  manager.spawn_worker(queue)
               end

               it 'should pass the worker the config' do
                  config.define_queue(:test_queue, test_task)

                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(config: config))
                                               .and_return(double('worker',
                                                                  work:      nil,
                                                                  start_log: nil,
                                                                  long_name: 'test-worker'))
                  manager.spawn_worker(queue)
               end

               it 'should pass the worker the queue settings' do
                  config.define_queue(:test_queue1, test_task,
                                      timeout:       1,
                                      max_attempts:  1,
                                      update_period: 1,
                                      max_tasks:     1)
                  config.define_queue(:test_queue2, test_task,
                                      timeout:       2,
                                      max_attempts:  2,
                                      update_period: 2,
                                      max_tasks:     2)

                  config.queues.each do |queue|
                     expect(QueueWorker).to receive(:new)
                                                  .with(hash_including(queue: queue))
                                                  .and_return(worker)
                     manager.spawn_worker(queue)
                  end
               end

               it 'should pass the worker the scheduler' do
                  scheduler = double('scheduler')

                  config.define_queue(:test2b, test_task)

                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(scheduler: scheduler))
                                               .and_return(worker)

                  manager.spawn_worker(config.queues.first, scheduler: scheduler)
               end

               it 'should run the each_process hook in each queue' do
                  subprocess_persister = double('child persister', read: nil, create: nil, update: nil, delete: nil)

                  expect(config).to receive(:load_with).with(subprocess_persister).ordered

                  config.each_process do
                     config.load_with(subprocess_persister)
                  end

                  config.define_queue(:test, test_task)

                  allow_any_instance_of(QueueWorker).to receive(:work)

                  expect(config).to receive(:run_process_block).and_call_original

                  manager.spawn_worker(queue)
               end

               it 'should run the each_process hook after running fork' do
                  manager = QueueManager.new(config)

                  subprocess_persister = double('child persister', read: nil, create: nil, update: nil, delete: nil)

                  config.each_process do
                     config.load_with(subprocess_persister)
                  end

                  config.define_queue(:test, test_task)

                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(config: config))
                                               .and_call_original
                  allow_any_instance_of(QueueWorker).to receive(:work)

                  expect(manager).to receive(:fork).and_return(nil).ordered
                  expect(config).to receive(:run_process_block).and_call_original.ordered

                  manager.spawn_worker(queue)
               end

               it 'should run the each_process hook before running work' do
                  worker               = double('worker', long_name: 'test-queue-worker')
                  subprocess_persister = Test::Persister.new

                  config.each_process do
                     config.load_with(subprocess_persister)
                  end

                  config.define_queue(:test, test_task)

                  allow(QueueWorker).to receive(:new).and_return(worker)

                  expect(config).to receive(:run_process_block).and_call_original.ordered
                  expect(worker).to receive(:work).ordered

                  manager.spawn_worker(queue)
               end

               it 'should pass the worker the config instance' do
                  subprocess_persister = double('child persister', read: nil, create: nil, update: nil, delete: nil)

                  config.each_process do
                     config.load_with(subprocess_persister)
                  end

                  config.define_queue(:test, test_task)

                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(config: config))
                                               .and_call_original
                  allow_any_instance_of(QueueWorker).to receive(:work)

                  manager.spawn_worker(queue)
               end

               it 'should name the worker process' do
                  [:test1, :test2, :test3].each do |name|
                     config.define_queue(name, test_task)

                     allow_any_instance_of(QueueWorker).to receive(:work)

                     expect(Process).to receive(:setproctitle).with("#{name}-queue-worker")

                     queue = Procrastinator::Queue.new(name: name, task_class: test_task)

                     manager.spawn_worker(queue)
                  end
               end

               it 'should name each worker process with provided prefix' do
                  [:app1, :app2, :app3].each do |prefix|
                     config.define_queue(:test_queue, test_task)
                     config.each_process(prefix: prefix)

                     allow_any_instance_of(QueueWorker).to receive(:work)

                     expect(Process).to receive(:setproctitle).with("#{prefix}-test_queue-queue-worker")

                     manager.spawn_worker(queue)
                  end
               end

               it 'should tell the worker process to work' do
                  queue = Procrastinator::Queue.new(name: :test, task_class: test_task)

                  worker = double('worker')

                  expect(worker).to receive(:work)
                  allow(worker).to receive(:long_name).and_return('worker-queue-worker')
                  allow(worker).to receive(:start_log)

                  allow(QueueWorker).to receive(:new).and_return(worker)

                  manager.spawn_worker(queue)
               end

               it 'should NOT store any pids' do
                  allow_any_instance_of(QueueWorker).to receive(:work)

                  manager.spawn_worker(queue)

                  expect(manager.workers).to be_empty
               end

               it 'should use a default log directory if not provided in setup' do
                  config.define_queue(:queue1, test_task)

                  allow_any_instance_of(QueueWorker).to receive(:work)

                  manager.spawn_worker(queue)

                  expect(File.directory?('log/')).to be true
               end

               it 'should never proceed past #work' do
                  config.define_queue(:queue1, test_task)

                  allow_any_instance_of(QueueWorker).to receive(:work)

                  expect(manager).to receive(:shutdown_worker).and_call_original

                  expect do
                     manager.spawn_worker(queue)
                  end.to raise_exception SystemExit
               end

               after(:each) do
                  # need to kill any processes that may be left over from failing tests.
                  `pgrep -f queue-worker`.split.each do |pid|
                     Process.kill('KILL', pid.to_i)
                  end
               end
            end
         end
      end

      describe '#act' do
         include FakeFS::SpecHelpers

         let(:persister) { double('persister', read: [], create: nil, update: nil, delete: nil) }

         let(:config) do
            config = Config.new
            config.load_with(persister)
            config.define_queue(:test1, test_task)
            config.define_queue(:test2, test_task)
            config.define_queue(:test3, test_task)
            config
         end

         let(:manager) { QueueManager.new(config) }

         before(:each) do
            config.enable_test_mode
            allow(manager).to receive(:fork).and_return(5, 6, 7)
            manager.spawn_workers
         end

         it 'should call QueueWorker#act on every queue worker' do
            expect(manager.workers.size).to eq 3

            manager.workers.keys.each do |worker|
               expect(worker).to receive(:act)
            end

            manager.act
         end

         it 'should call QueueWorker#act on queue worker for given queues only' do
            workers = manager.workers.keys

            worker1 = workers.find { |w| w.name == :test1 }
            worker2 = workers.find { |w| w.name == :test2 }
            worker3 = workers.find { |w| w.name == :test3 }

            expect(worker1).to_not receive(:act)
            expect(worker2).to receive(:act)
            expect(worker3).to receive(:act)

            manager.act(:test2, :test3)
         end

         it 'should not complain when using Procrastinator.act in Test Mode' do
            expect { manager.act }.to_not raise_error
         end

         it 'should complain if you try to use Procrastinator.act outside Test Mode' do
            config = Config.new
            config.load_with(persister)

            normal_manager = QueueManager.new(config)

            err = <<~ERR
               Procrastinator.act called outside Test Mode.
               Either use Procrastinator.spawn_workers or call #enable_test_mode in Procrastinator.setup.
            ERR

            expect { normal_manager.act }.to raise_error RuntimeError, err
         end
      end
   end
end
