require 'spec_helper'

module Procrastinator
   describe QueueManager do
      let(:test_task) {Test::Task::AllHooks}

      describe '#spawn_workers' do
         let(:persister) {Test::Persister.new}
         let(:config) do
            config = Config.new
            config.load_with(persister)
            config
         end

         let(:manager) {QueueManager.new(config)}

         before do
            FakeFS.activate!
         end

         after do
            if FakeFS.activated?
               FileUtils.rm_rf('/*')
            end

            FakeFS.deactivate!
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

            it 'should pass each queue the evaluated persister instance' do
               queue_defs = [:test2a, :test2b, :test2c]
               queue_defs.each do |name|
                  config.define_queue(name, test_task)
               end

               queue_defs.each do
                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(persister: persister))
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

            it 'should evaluate load_with and pass it to the worker' do
               persister = double('specific persister', read_tasks: nil, create_task: nil, update_task: nil, delete_task: nil)

               config.load_with(persister)

               config.define_queue(:test, test_task)

               expect(QueueWorker).to receive(:new).with(hash_including(persister: persister)).and_call_original

               manager.spawn_workers
            end

            it 'should evaluate task_context and pass it to the worker' do
               context = double('task context')

               config.provide_context(context)
               config.define_queue(:queue_name, test_task)

               expect(QueueWorker).to receive(:new)
                                            .with(hash_including(task_context: context))
                                            .and_return(double('worker',
                                                               work:      nil,
                                                               start_log: nil,
                                                               long_name: ''))

               manager.spawn_workers
            end

            it 'should return a scheduler with the same config' do
               expect(Scheduler).to receive(:new).with(config).and_call_original

               expect(manager.spawn_workers).to be_a Scheduler
            end
         end

         context 'live mode' do
            context 'parent process' do
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

               it 'should record its spawned processes' do
                  config.define_queue(:test1, test_task)
                  config.define_queue(:test2, test_task)
                  config.define_queue(:test3, test_task)

                  pid1 = 10
                  pid2 = 11
                  pid3 = 12

                  allow(manager).to receive(:fork).and_return(pid1, pid2, pid3)

                  manager.spawn_workers

                  expect(manager.workers).to eq [pid1, pid2, pid3]
               end

               it 'should store the PID of children in the manager' do
                  allow(manager).to receive(:fork).and_return(1, 2, 3)

                  config.define_queue(:test1, test_task)
                  config.define_queue(:test2, test_task)
                  config.define_queue(:test3, test_task)

                  manager.spawn_workers

                  expect(manager.workers).to eq [1, 2, 3]
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

               it 'should pass the worker default log settings' do
                  config.define_queue(:test_queue, test_task)

                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(log_dir:   Config::DEFAULT_LOG_DIRECTORY,
                                                                    log_level: Logger::INFO))
                                               .and_return(double('worker',
                                                                  work:      nil,
                                                                  start_log: nil,
                                                                  long_name: ''))
                  manager.spawn_workers
               end

               it 'should pass the worker the logging settings' do
                  dir = double('dir')
                  lvl = double('lvl')

                  config.define_queue(:test_queue, test_task)

                  config.log_inside(dir)
                  config.log_at_level(lvl)

                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(log_dir:   dir,
                                                                    log_level: lvl))
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
                  subprocess_persister = double('child persister', read_tasks: nil, create_task: nil, update_task: nil, delete_task: nil)

                  config.each_process do
                     config.load_with(subprocess_persister)
                  end

                  config.define_queue(:test, test_task)

                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(persister: subprocess_persister))
                                               .and_call_original
                  allow_any_instance_of(QueueWorker).to receive(:work)

                  manager.spawn_workers
               end

               it 'should run the each_process hook after running fork' do
                  manager = QueueManager.new(config)

                  subprocess_persister = double('child persister', read_tasks: nil, create_task: nil, update_task: nil, delete_task: nil)

                  config.each_process do
                     config.load_with(subprocess_persister)
                  end

                  config.define_queue(:test, test_task)

                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(persister: subprocess_persister))
                                               .and_call_original
                  allow_any_instance_of(QueueWorker).to receive(:work)

                  expect(manager).to receive(:fork).and_return(nil).ordered
                  expect(config).to receive(:run_process_block).and_call_original.ordered

                  manager.spawn_workers
               end

               it 'should run the each_process hook before running work' do
                  subprocess_persister = Test::Persister.new

                  config.each_process do
                     config.load_with(subprocess_persister)
                  end

                  config.define_queue(:test, test_task)

                  expect(config).to receive(:run_process_block).and_call_original.ordered
                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(persister: subprocess_persister))
                                               .and_call_original
                                               .ordered
                  allow_any_instance_of(QueueWorker).to receive(:work)

                  manager.spawn_workers
               end

               it 'should pass the worker the loader instance' do
                  subprocess_persister = double('child persister', read_tasks: nil, create_task: nil, update_task: nil, delete_task: nil)

                  config.each_process do
                     config.load_with(subprocess_persister)
                  end

                  config.define_queue(:test, test_task)

                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(persister: subprocess_persister))
                                               .and_call_original
                  allow_any_instance_of(QueueWorker).to receive(:work)

                  manager.spawn_workers
               end

               it 'should provide the worker the task context' do
                  context = double('task context')

                  config.each_process do
                     config.provide_context(context)
                  end
                  config.define_queue(:queue_name, test_task)

                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(task_context: context))
                                               .and_return(double('worker',
                                                                  work:      nil,
                                                                  start_log: nil,
                                                                  long_name: ''))

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

               it 'should monitor the parent process' do
                  config.define_queue(:test, test_task)

                  parent_pid = 10

                  allow_any_instance_of(QueueWorker).to receive(:work)

                  allow(Process).to receive(:pid).and_return(parent_pid)

                  allow(Thread).to receive(:new) do |&block|
                     begin
                        block.call(parent_pid)
                     rescue Errno::ESRCH
                        exit
                     end

                     thread = double('thread double')

                     allow(thread).to receive(:abort_on_exception=).with(true)

                     thread
                  end

                  # control looping, otherwise infiniloop by design
                  allow(manager).to receive(:sleep)
                  allow(manager).to receive(:loop) do |&block|
                     block.call
                  end

                  expect(Process).to receive(:kill).with(0, parent_pid)

                  manager.spawn_workers

                  allow(Process).to receive(:pid).and_call_original
                  allow(Process).to receive(:kill).and_call_original
               end

               it 'should exit if the parent process dies' do
                  exited = false

                  config.define_queue(:test, test_task)

                  parent_pid = 10

                  allow_any_instance_of(QueueWorker).to receive(:work)
                  allow_any_instance_of(QueueWorker).to receive(:log_parent_exit)

                  allow(Process).to receive(:kill).with(0, parent_pid).and_raise(Errno::ESRCH)

                  allow(Thread).to receive(:new) do |&block|
                     block.call(parent_pid)
                  end

                  # control looping, otherwise infiniloop by design
                  allow(manager).to receive(:sleep)
                  allow(manager).to receive(:loop) do |&block|
                     block.call
                  end

                  begin
                     manager.spawn_workers
                  rescue SystemExit
                     # this is safer than stubbing exit, which can have weird consequences on the test system
                     exited = true
                  end

                  expect(exited).to be true
               end

               it 'should use a default log directory if not provided in setup' do
                  config.define_queue(:queue1, test_task)

                  allow_any_instance_of(QueueWorker).to receive(:work)

                  manager.spawn_workers

                  expect(File.directory?('log/')).to be true
               end

               it 'should get each worker to start its log' do
                  config.define_queue(:queue1, test_task)
                  config.define_queue(:queue2, test_task)

                  config.log_inside('some_dir/')

                  allow_any_instance_of(QueueWorker).to receive(:work)

                  manager.spawn_workers

                  expect(File.file?('some_dir/queue1-queue-worker.log')).to be true
                  expect(File.file?('some_dir/queue2-queue-worker.log')).to be true
               end

               it 'should log exiting when parent process dies' do
                  config.define_queue(:test, test_task)

                  parent_pid = 10
                  child_pid  = 2000

                  allow_any_instance_of(QueueWorker).to receive(:work)

                  allow(Process).to receive(:kill).with(0, parent_pid).and_raise(Errno::ESRCH)
                  allow(Process).to receive(:ppid).and_return(parent_pid)
                  allow(Process).to receive(:pid).and_return(child_pid)

                  allow(Thread).to receive(:new) do |&block|
                     block.call(parent_pid)
                  end

                  # control looping, otherwise infiniloop by design
                  allow(manager).to receive(:sleep)
                  allow(manager).to receive(:loop) do |&block|
                     block.call
                  end

                  begin
                     manager.spawn_workers
                  rescue SystemExit
                     # this is safer than stubbing exit, which can have weird consequences on the test system
                  end

                  log_path = 'log/test-queue-worker.log'

                  expect(File.read(log_path)).to include('Terminated worker process')
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
         let(:persister) {double('persister', read_tasks: [], create_task: nil, update_task: nil, delete_task: nil)}

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
            manager.spawn_workers
         end

         it 'should call QueueWorker#act on every queue worker' do
            expect(manager.workers.size).to eq 3
            manager.workers.each do |worker|
               expect(worker).to receive(:act)
            end

            manager.act
         end

         it 'should call QueueWorker#act on queue worker for given queues only' do
            expect(manager.workers[0]).to_not receive(:act)
            expect(manager.workers[1]).to receive(:act)
            expect(manager.workers[2]).to receive(:act)

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

            expect {normal_manager.act}.to raise_error(RuntimeError,)
         end
      end
   end
end
