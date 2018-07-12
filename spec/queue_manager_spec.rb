require 'spec_helper'

module Procrastinator
   describe QueueManager do
      let(:test_task) {Test::Task::AllHooks}

      describe '#initialize' do
         include FakeFS::SpecHelpers

         let(:config) {Config.new}

         before(:each) do
            FileUtils.rm_rf('/*') if FakeFS.activated?
         end

         it 'should start a log file for the main process' do
            QueueManager.new(config)

            expect(File).to exist("#{config.log_dir}/queue-manager.log")
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

         let(:persister) {Test::Persister.new}
         let(:config) do
            config = Config.new
            config.load_with(persister)
            config
         end

         let(:manager) {QueueManager.new(config)}

         before(:each) do
            FileUtils.rm_rf('/*') if FakeFS.activated?
         end

         context 'test mode' do
            before(:each) do
               config.enable_test_mode
            end

            it 'should create a worker for each queue definition' do
               queue_defs = [:test2a, :test2b, :test2c]
               queue_defs.each do |name|
                  config.define_queue(name, test_task)
               end

               queue_defs.each do |name|
                  expect(QueueWorker).to receive(:new)
                                               .with(satisfy do |arg|
                                                  arg[:queue].name == name && arg[:queue].task_class == test_task
                                               end)
                                               .and_return(double('worker', work: nil))
               end

               manager.spawn_workers
            end

            it 'should pass each worker a queue object from config' do
               config.define_queue(:test2a, test_task, max_attempts: 1, timeout: 1, update_period: 1, max_tasks: 1)
               config.define_queue(:test2b, test_task, max_attempts: 2, timeout: 2, update_period: 2, max_tasks: 2)

               config.queues.each do |queue|
                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(queue: queue))
                                               .and_return(double('worker', work: nil))
               end

               manager.spawn_workers
            end

            it 'should pass each worker the scheduler' do
               scheduler = double('scheduler')

               allow(Scheduler).to receive(:new).and_return(scheduler)

               config.define_queue(:test2a, test_task, max_attempts: 1, timeout: 1, update_period: 1, max_tasks: 1)
               config.define_queue(:test2b, test_task, max_attempts: 2, timeout: 2, update_period: 2, max_tasks: 2)

               config.queues.each do
                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(scheduler: scheduler))
                                               .and_return(double('worker', work: nil))
               end

               expect(manager.spawn_workers).to be scheduler
            end

            it 'should pass each queue the config instance' do
               queue_defs = [:test2a, :test2b, :test2c]
               queue_defs.each do |name|
                  config.define_queue(name, test_task)
               end

               queue_defs.each do
                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(config: config))
                                               .and_return(double('worker', work: nil))
               end

               manager.spawn_workers
            end

            it 'should not fork' do
               config.define_queue(:test, test_task)

               expect(manager).to_not receive(:fork)

               manager.spawn_workers
            end

            it 'should not call #work' do
               config.define_queue(:test, test_task)

               expect_any_instance_of(QueueWorker).to_not receive(:work)

               manager.spawn_workers
            end

            it 'should NOT change the process title' do
               config.define_queue(:test, test_task)

               expect(Process).to_not receive(:setproctitle)

               manager.spawn_workers
            end

            it 'should NOT open a log file' do
               queue_name = :queue1

               config.define_queue(queue_name, test_task)

               FakeFS do
                  manager.spawn_workers

                  expect(File.file?("log/#{queue_name}-queue-worker.log")).to be false
               end
            end

            it 'should evaluate pass the config to the worker' do
               config.load_with double('specific persister', read: nil, create: nil, update: nil, delete: nil)

               config.define_queue(:test, test_task)

               expect(QueueWorker).to receive(:new).with(hash_including(config: config)).and_call_original

               manager.spawn_workers
            end

            it 'should return a scheduler with the same config' do
               expect(Scheduler).to receive(:new).with(config).and_call_original

               expect(manager.spawn_workers).to be_a Scheduler
            end
         end

         context 'live mode' do
            context 'parent process' do
               include FakeFS::SpecHelpers

               before(:each) do
                  allow(Process).to receive(:detach)
               end

               it 'should fork a worker process' do
                  config.define_queue(:test, test_task)

                  expect(manager).to receive(:fork).once.and_return(double('a child pid'))

                  manager.spawn_workers
               end

               it 'should fork a worker process for each queue' do
                  queue_defs = [:test2a, :test2b, :test2c]
                  queue_defs.each do |name|
                     config.define_queue(name, test_task)
                  end

                  expect(manager).to receive(:fork).exactly(queue_defs.size).times.and_return(double('a child pid'))

                  manager.spawn_workers
               end

               it 'should not wait for the QueueWorker' do
                  config.define_queue(:test1, test_task)
                  config.define_queue(:test2, test_task)
                  config.define_queue(:test3, test_task)

                  Timeout::timeout(1) do
                     pid  = double('pid')
                     pid2 = double('pid2')
                     pid3 = double('pid3')

                     allow(manager).to receive(:fork).and_return(pid, pid2, pid3)

                     expect(Process).to receive(:detach).with(pid)
                     expect(Process).to receive(:detach).with(pid2)
                     expect(Process).to receive(:detach).with(pid3)

                     manager.spawn_workers
                  end
               end

               it 'should store the PID of children in the manager' do
                  worker1 = double('queue worker 1', long_name: 'work1')
                  worker2 = double('queue worker 2', long_name: 'work2')
                  worker3 = double('queue worker 3', long_name: 'work3')

                  allow(manager).to receive(:fork).and_return(11, 12, 13)
                  allow(QueueWorker).to receive(:new).and_return worker1, worker2, worker3

                  config.define_queue(:test1, test_task)
                  config.define_queue(:test2, test_task)
                  config.define_queue(:test3, test_task)

                  manager.spawn_workers

                  expect(manager.workers).to eq(worker1 => 11, worker2 => 12, worker3 => 13)
               end

               it 'should write a PID file for each child within the pid directory' do
                  config.prefix_processes 'myapp'

                  config.define_queue(:test1, test_task)
                  config.define_queue(:test2, test_task)
                  config.define_queue(:test3, test_task)

                  pid1 = 10
                  pid2 = 11
                  pid3 = 12

                  allow(manager).to receive(:fork).and_return(pid1, pid2, pid3)

                  manager.spawn_workers

                  expect(File).to exist('pid/myapp-test1-queue-worker.pid')
                  expect(File).to exist('pid/myapp-test2-queue-worker.pid')
                  expect(File).to exist('pid/myapp-test3-queue-worker.pid')
               end

               it 'should write PID files in the given directory' do
                  %w[/var/pid
                     some/pid/place].each do |dir|

                     config.save_pids_in dir

                     config.define_queue(:test1, test_task)

                     pid = 18

                     allow(manager).to receive(:fork).and_return(pid)

                     manager.spawn_workers

                     expect(File).to exist("#{dir}/test1-queue-worker.pid")
                  end
               end

               it 'should store the child PID in that queue pid file' do
                  config.prefix_processes 'myapp'

                  config.define_queue(:test1, test_task)
                  config.define_queue(:test2, test_task)

                  pid1 = 2543
                  pid2 = 15845

                  allow(manager).to receive(:fork).and_return(pid1, pid2)

                  manager.spawn_workers

                  queue1_file = File.read('pid/myapp-test1-queue-worker.pid')
                  queue2_file = File.read('pid/myapp-test2-queue-worker.pid')

                  expect(queue1_file).to eq pid1.to_s
                  expect(queue2_file).to eq pid2.to_s
               end

               it 'should kill all PIDs found in the files before forking' do
                  pid1 = 1192
                  pid2 = 12907

                  FileUtils.mkpath 'pid/'
                  File.open('pid/test1-queue-worker.pid', 'w') {|f| f.print pid1}
                  File.open('pid/test2-queue-worker.pid', 'w') {|f| f.print pid2}

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
                  File.open('pid/test1-queue-worker.pid', 'w') {|f| f.print pid1}
                  File.open('pid/test2-queue-worker.pid', 'w') {|f| f.print pid2}

                  expect(manager).to_not receive(:fork)
                  allow(Process).to receive(:kill)

                  manager.spawn_workers

                  expect(Pathname.new(dir)).to be_empty
               end

               it 'should log all killed PIDs' do
                  pid1 = 5411
                  pid2 = 13134

                  FileUtils.mkpath 'pid/'
                  File.open('pid/test1-queue-worker.pid', 'w') {|f| f.print pid1}
                  File.open('pid/test2-queue-worker.pid', 'w') {|f| f.print pid2}

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
                  File.open('pid/test1-queue-worker.pid', 'w') {|f| f.print missing_pid}
                  File.open('pid/test2-queue-worker.pid', 'w') {|f| f.print old_pid}

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
                  File.open('pid/test1-queue-worker.pid', 'w') {|f| f.print pid}

                  expect(manager).to_not receive(:fork) # sanity/protection
                  allow(Process).to receive(:kill).and_raise Errno::ESRCH

                  manager.spawn_workers

                  log = File.read('log/queue-manager.log')

                  expect(log).to include("Expected old worker process pid=#{pid}, but none was found")
               end

               it 'should NOT fork when ENV variable PROCRASTINATOR_STOP is enabled' do
                  old_stop = ENV['PROCRASTINATOR_STOP']

                  ENV['PROCRASTINATOR_STOP'] = 'true'

                  queue_defs = [:test2a, :test2b, :test2c]
                  queue_defs.each do |name|
                     config.define_queue(name, test_task)
                  end

                  expect(manager).to_not receive(:fork)

                  manager.spawn_workers

                  ENV['PROCRASTINATOR_STOP'] = old_stop
               end

               it 'should still remove old processes when ENV variable PROCRASTINATOR_STOP is enabled' do
                  old_stop = ENV['PROCRASTINATOR_STOP']

                  ENV['PROCRASTINATOR_STOP'] = 'true'

                  FileUtils.mkpath 'pid/'
                  File.open('pid/test1-queue-worker.pid', 'w') {|f| f.print 144}

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

               it 'should return a scheduler with the same config' do
                  expect(Scheduler).to receive(:new).with(config).and_call_original

                  expect(manager.spawn_workers).to be_a Scheduler
               end

               it 'should NOT run the each_process hook' do
                  run = false

                  config.each_process do
                     run = true
                  end

                  config.define_queue(:test, test_task)

                  expect(config).to_not receive(:subprocess_block)
                  expect(run).to be false

                  manager.spawn_workers
               end
            end

            context 'subprocess' do
               let(:worker) {double('worker',
                                    work:      nil,
                                    start_log: nil,
                                    long_name: '')}

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
                                                                  long_name: ''))
                  manager.spawn_workers
               end

               it 'should pass the worker the config' do
                  config.define_queue(:test_queue, test_task)

                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(config: config))
                                               .and_return(double('worker',
                                                                  work:      nil,
                                                                  start_log: nil,
                                                                  long_name: ''))
                  manager.spawn_workers
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
                  end

                  manager.spawn_workers
               end

               it 'should pass each worker the scheduler' do
                  scheduler = double('scheduler')

                  expect(Scheduler).to receive(:new).with(config).and_return(scheduler)

                  config.define_queue(:test2a, test_task)
                  config.define_queue(:test2b, test_task)

                  config.queues.each do
                     expect(QueueWorker).to receive(:new)
                                                  .with(hash_including(scheduler: scheduler))
                                                  .and_return(worker)
                  end

                  expect(manager.spawn_workers).to be scheduler
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

                  manager.spawn_workers
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

                  manager.spawn_workers
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

                  manager.spawn_workers
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

                  manager.spawn_workers
               end

               it 'should name each worker process' do
                  queues = [:test1, :test2, :test3]
                  queues.each do |name|
                     config.define_queue(name, test_task)
                  end

                  allow_any_instance_of(QueueWorker).to receive(:work)

                  queues.each do |name|
                     expect(Process).to receive(:setproctitle).with("#{name}-queue-worker")
                  end

                  manager.spawn_workers
               end

               it 'should name each worker process with provided prefix' do
                  [:app1, :app2, :app3].each do |prefix|
                     config.define_queue(:test_queue, test_task)
                     config.prefix_processes(prefix)

                     allow_any_instance_of(QueueWorker).to receive(:work)

                     expect(Process).to receive(:setproctitle).with("#{prefix}-test_queue-queue-worker")

                     manager.spawn_workers
                  end
               end

               it 'should tell the worker process to work' do
                  config.define_queue(:test1, test_task)
                  config.define_queue(:test2, test_task)
                  config.define_queue(:test3, test_task)

                  worker1 = double('worker1')
                  worker2 = double('worker2')
                  worker3 = double('worker3')

                  [worker1, worker2, worker3].each do |worker|
                     expect(worker).to receive(:work)

                     allow(worker).to receive(:start_log)
                     allow(worker).to receive(:long_name)
                  end

                  allow(QueueWorker).to receive(:new).and_return(worker1, worker2, worker3)

                  manager.spawn_workers
               end

               it 'should NOT store any pids' do
                  manager.spawn_workers

                  expect(manager.workers).to be_empty
               end

               it 'should use a default log directory if not provided in setup' do
                  config.define_queue(:queue1, test_task)

                  allow_any_instance_of(QueueWorker).to receive(:work)

                  manager.spawn_workers

                  expect(File.directory?('log/')).to be true
               end

               it 'should never proceed past #work' do
                  config.define_queue(:queue1, test_task)

                  allow_any_instance_of(QueueWorker).to receive(:work)

                  expect(manager).to receive(:shutdown_worker).and_call_original

                  expect do
                     manager.spawn_workers
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

         let(:persister) {double('persister', read: [], create: nil, update: nil, delete: nil)}

         let(:config) do
            config = Config.new
            config.load_with(persister)
            config.define_queue(:test1, test_task)
            config.define_queue(:test2, test_task)
            config.define_queue(:test3, test_task)
            config
         end

         let(:manager) {QueueManager.new(config)}

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

            worker1 = workers.find {|w| w.name == :test1}
            worker2 = workers.find {|w| w.name == :test2}
            worker3 = workers.find {|w| w.name == :test3}

            expect(worker1).to_not receive(:act)
            expect(worker2).to receive(:act)
            expect(worker3).to receive(:act)

            manager.act(:test2, :test3)
         end

         it 'should not complain when using Procrastinator.act in Test Mode' do
            expect {manager.act}.to_not raise_error
         end

         it 'should complain if you try to use Procrastinator.act outside Test Mode' do
            config = Config.new
            config.load_with(persister)

            normal_manager = QueueManager.new(config)

            err = <<~ERR
               Procrastinator.act called outside Test Mode. 
               Either use Procrastinator.spawn_workers or call #enable_test_mode in Procrastinator.setup.
            ERR

            expect {normal_manager.act}.to raise_error RuntimeError, err
         end
      end
   end
end