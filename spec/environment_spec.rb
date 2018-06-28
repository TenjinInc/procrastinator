module Procrastinator
   require 'spec_helper'
   require 'timeout'

   describe Environment do
      describe '#initialize' do
         let(:config) {Config.new}

         it 'should complain if the task loader is nil' do
            config.load_with do
               nil
            end

            expect do
               Environment.new(config)
            end.to raise_error(MalformedTaskLoaderError, 'task loader cannot be nil')
         end

         it 'should require the persister respond to #read_tasks' do
            loader = double('persister', create_task: nil, update_task: nil, delete_task: nil)

            config.load_with do
               loader
            end

            expect do
               Environment.new(config)
            end.to raise_error(MalformedTaskLoaderError, "task loader #{loader.class} must respond to #read_tasks")
         end

         it 'should require the persister respond to #create_task' do
            loader = double('persister', read_tasks: nil, update_task: nil, delete_task: nil)

            config.load_with do
               loader
            end

            expect do
               Environment.new(config)
            end.to raise_error(MalformedTaskLoaderError, "task loader #{loader.class} must respond to #create_task")
         end

         it 'should require the persister respond to #update_task' do
            loader = double('persister', read_tasks: nil, create_task: nil, delete_task: nil)

            config.load_with do
               loader
            end

            expect do
               Environment.new(config)
            end.to raise_error(MalformedTaskLoaderError, "task loader #{loader.class} must respond to #update_task")
         end

         it 'should require the persister respond to #delete_task' do
            loader = double('persister', read_tasks: nil, create_task: nil, update_task: nil)

            config.load_with do
               loader
            end

            expect do
               Environment.new(config)
            end.to raise_error(MalformedTaskLoaderError, "task loader #{loader.class} must respond to #delete_task")
         end
      end

      describe '#delay' do
         # api: Procrastinator.delay(run_at: Time.now + 10, queue: :email, SendInvitation.new(to: 'bob@example.com'))

         let(:persister) {double('persister', read_tasks: [], create_task: nil, update_task: nil, delete_task: nil)}
         let(:config) do
            config = Config.new
            config.load_with do
               persister
            end
            config.define_queue(:test_queue, Test::Task::AllHooks)
            config
         end

         let(:env) {Environment.new(config)}

         it 'should record a task on the given queue' do
            [:queue1, :queue2].each do |queue_name|
               config.define_queue(queue_name, Test::Task::AllHooks)

               expect(persister).to receive(:create_task).with(include(queues: queue_name))

               env.delay(queue_name)
            end
         end

         it 'should record a task with given run_at' do
            run_stamp = double('runstamp')

            expect(persister).to receive(:create_task).with(include(run_at: run_stamp))

            env.delay(:test_queue, run_at: double('time_object', to_i: run_stamp))
         end

         it 'should record a task with given expire_at' do
            expire_stamp = double('expirestamp')

            expect(persister).to receive(:create_task).with(include(expire_at: expire_stamp))

            env.delay(:test_queue, expire_at: double('time_object', to_i: expire_stamp))
         end

         it 'should record a task with serialized task data' do
            data = double('some_data')

            # these are, at the moment, all of the arguments the dev can pass in
            expect(persister).to receive(:create_task).with(include(data: YAML.dump(data)))

            env.delay(data: data)
         end

         it 'should default run_at to now' do
            now = Time.now

            Timecop.freeze(now) do
               expect(persister).to receive(:create_task).with(include(run_at: now.to_i))

               env.delay()
            end
         end

         it 'should record initial_run_at and run_at to be equal' do
            time = Time.now

            expect(persister).to receive(:create_task).with(include(run_at: time.to_i, initial_run_at: time.to_i))

            env.delay(run_at: time)
         end

         it 'should record convert run_at, initial_run_at, expire_at to ints' do
            expect(persister).to receive(:create_task).with(include(run_at: 0, initial_run_at: 0, expire_at: 1))

            env.delay(run_at:    double('time', to_i: 0),
                      expire_at: double('time', to_i: 1))
         end

         it 'should default expire_at to nil' do
            expect(persister).to receive(:create_task).with(include(expire_at: nil))

            env.delay
         end

         it 'should NOT complain about well-formed hooks' do
            [:success, :fail, :final_fail].each do |method|
               task = Test::Task::AllHooks.new

               # allow(task).to receive(method).with('')

               expect do
                  env.delay
               end.to_not raise_error
            end
         end

         it 'should require queue be provided if there is more than one queue defined' do
            config.define_queue(:queue1, Test::Task::AllHooks)
            config.define_queue(:queue2, Test::Task::AllHooks)

            msg = "queue must be specified when more than one is registered. Defined queues are: :test_queue, :queue1, :queue2"

            "queue must be specified when more than one is registered. Defined queues are: :test_queue, :queue1, :queue2"
            "queue must be specified when more than one is registered. Defined queues are: test_queue, queue1, queue2"

            expect {env.delay(run_at: 0)}.to raise_error(ArgumentError, msg)

            # also test the negative
            expect {env.delay(:queue1, run_at: 0)}.to_not raise_error
         end

         it 'should NOT require queue be provided if there only one queue defined' do
            config = Config.new
            config.load_with do
               persister
            end
            config.define_queue(:queue_name, Test::Task::AllHooks)
            env = Environment.new config

            expect {env.delay}.to_not raise_error
         end

         it 'should assume the queue name if there only one queue defined' do
            config = Config.new
            config.load_with do
               persister
            end
            config.define_queue(:some_queue, Test::Task::AllHooks)
            env = Environment.new config

            expect(persister).to receive(:create_task).with(include(queues: :some_queue))

            env.delay
         end
         #there is no :bogus queue registered. Defined queues are: :test_queue, :another_queue
         #there is no :bogus queue registered. Defined queues are: :test_queue, :another_queue
         it 'should complain when the given queue is not registered' do
            config.define_queue(:another_queue, Test::Task::AllHooks)

            [:bogus, :other_bogus].each do |name|
               err = %[there is no :#{name} queue registered. Defined queues are: :test_queue, :another_queue]

               expect {env.delay(name, run_at: 0)}.to raise_error(ArgumentError, err)
            end
         end
      end

      describe '#spawn_workers' do
         let(:persister) {double('persister', read_tasks: [], create_task: [], update_task: [], delete_task: [])}
         let(:config) do
            config = Config.new
            config.load_with do
               persister
            end
            config
         end

         let(:env) {Environment.new(config)}

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

            let(:test_task) {Test::Task::AllHooks}

            it 'should create a worker for each queue definition' do
               queue_defs = [:test2a, :test2b, :test2c]
               queue_defs.each do |name|
                  config.define_queue(name, test_task)
               end

               queue_defs.each do |name|
                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(persister:  persister,
                                                                    name:       name,
                                                                    task_class: test_task))
                                               .and_return(double('worker', work: nil))
               end

               env.spawn_workers
            end

            it 'should pass each worker the queue properties' do
               queue_defs = {test2a: {max_attempts: 1, timeout: 1, update_period: 1, max_tasks: 1},
                             test2b: {max_attempts: 2, timeout: 2, update_period: 2, max_tasks: 2}}
               queue_defs.each do |name, props|
                  config.define_queue(name, test_task, props)
               end

               queue_defs.values.each do |props|
                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(props))
                                               .and_return(double('worker', work: nil))
               end

               env.spawn_workers
            end

            it 'should not fork' do
               config.define_queue(:test, test_task)

               expect(env).to_not receive(:fork)

               env.spawn_workers
            end

            it 'should not call #work' do
               config.define_queue(:test, test_task)

               expect_any_instance_of(QueueWorker).to_not receive(:work)

               env.spawn_workers
            end

            it 'should NOT change the process title' do
               config.define_queue(:test, test_task)

               expect(Process).to_not receive(:setproctitle)

               env.spawn_workers
            end

            it 'should NOT open a log file' do
               queue_name = :queue1

               config.define_queue(queue_name, test_task)

               FakeFS do
                  env.spawn_workers

                  expect(File.file?("log/#{queue_name}-queue-worker.log")).to be false
               end
            end

            it 'should evaluate load_with and pass it to the worker' do
               persister = double('persister', read_tasks: nil, create_task: nil, update_task: nil, delete_task: nil)

               config.load_with do
                  persister
               end

               config.define_queue(:test, test_task)

               expect(QueueWorker).to receive(:new).with(hash_including(persister: persister)).and_call_original

               env.spawn_workers
            end

            it 'should evaluate task_context and pass it to the worker' do
               context = double('task context')

               config.provide_context do
                  context
               end
               config.define_queue(:queue_name, test_task)

               expect(QueueWorker).to receive(:new)
                                            .with(hash_including(task_context: context))
                                            .and_return(double('worker',
                                                               work:      nil,
                                                               start_log: nil,
                                                               long_name: ''))

               env.spawn_workers
            end
         end

         context 'live mode' do
            let(:test_task) {Test::Task::AllHooks}

            context 'parent process' do
               before(:each) do
                  allow(Process).to receive(:detach)
               end

               it 'should fork a worker process' do
                  config.define_queue(:test, test_task)

                  expect(env).to receive(:fork).once.and_return(double('a child pid'))

                  env.spawn_workers
               end

               it 'should fork a worker process for each queue' do
                  queue_defs = [:test2a, :test2b, :test2c]
                  queue_defs.each do |name|
                     config.define_queue(name, test_task)
                  end

                  expect(env).to receive(:fork).exactly(queue_defs.size).times.and_return(double('a child pid'))

                  env.spawn_workers
               end

               it 'should not wait for the QueueWorker' do
                  config.define_queue(:test1, test_task)
                  config.define_queue(:test2, test_task)
                  config.define_queue(:test3, test_task)

                  Timeout::timeout(1) do
                     pid  = double('pid')
                     pid2 = double('pid2')
                     pid3 = double('pid3')

                     allow(env).to receive(:fork).and_return(pid, pid2, pid3)

                     expect(Process).to receive(:detach).with(pid)
                     expect(Process).to receive(:detach).with(pid2)
                     expect(Process).to receive(:detach).with(pid3)

                     env.spawn_workers
                  end
               end

               it 'should record its spawned processes' do
                  config.define_queue(:test1, test_task)
                  config.define_queue(:test2, test_task)
                  config.define_queue(:test3, test_task)

                  pid1 = 10
                  pid2 = 11
                  pid3 = 12

                  allow(env).to receive(:fork).and_return(pid1, pid2, pid3)

                  env.spawn_workers

                  expect(env.processes).to eq [pid1, pid2, pid3]
               end

               it 'should store the PID of children in the ENV' do
                  allow(env).to receive(:fork).and_return(1, 2, 3)

                  config.define_queue(:test1, test_task)
                  config.define_queue(:test2, test_task)
                  config.define_queue(:test3, test_task)

                  env.spawn_workers

                  expect(env.processes).to eq [1, 2, 3]
               end
            end

            context 'subprocess' do
               before(:each) do
                  allow(Process).to receive(:setproctitle)
                  allow(env).to receive(:fork).and_return(nil)
               end

               it 'should create a QueueWorker' do
                  config.define_queue(:test_queue, test_task)

                  expect(QueueWorker).to receive(:new)
                                               .once
                                               .and_return(double('worker',
                                                                  work:      nil,
                                                                  start_log: nil,
                                                                  long_name: ''))
                  env.spawn_workers
               end

               it 'should pass the worker default log settings' do
                  config.define_queue(:test_queue, test_task)

                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(log_dir:   Environment::DEFAULT_LOG_DIRECTORY,
                                                                    log_level: Logger::INFO))
                                               .and_return(double('worker',
                                                                  work:      nil,
                                                                  start_log: nil,
                                                                  long_name: ''))
                  env.spawn_workers
               end

               it 'should pass the worker the logging settings' do
                  props1 = {dir:   '/some/directory/',
                            level: Logger::DEBUG}
                  props2 = {dir:   '/another/good/place',
                            level: Logger::FATAL}

                  [props1, props2].each do |log_props|
                     config.define_queue(:test_queue, test_task)

                     config.log_in(log_props[:dir])
                     config.log_at_level(log_props[:level])

                     expect(QueueWorker).to receive(:new)
                                                  .with(hash_including(persister:  persister,
                                                                       task_class: test_task,
                                                                       log_dir:    log_props[:dir],
                                                                       log_level:  log_props[:level]))
                                                  .and_return(double('worker',
                                                                     work:      nil,
                                                                     start_log: nil,
                                                                     long_name: ''))
                     env.spawn_workers
                  end
               end

               it 'should pass the worker the queue settings' do
                  props1 = {timeout:       1,
                            max_attempts:  1,
                            update_period: 1,
                            max_tasks:     1}
                  props2 = {timeout:       2,
                            max_attempts:  2,
                            update_period: 2,
                            max_tasks:     2}

                  config.define_queue(:test_queue1, test_task, props1)
                  config.define_queue(:test_queue2, test_task, props2)

                  [props1, props2].each do |props|
                     expect(QueueWorker).to receive(:new)
                                                  .with(hash_including(props))
                                                  .and_return(double('worker',
                                                                     work:      nil,
                                                                     start_log: nil,
                                                                     long_name: ''))
                  end

                  env.spawn_workers
               end

               it 'should pass the worker a new loader instance' do
                  subprocess_persister = double('child persister', read_tasks: nil, create_task: nil, update_task: nil, delete_task: nil)

                  config.load_with do
                     subprocess_persister
                  end

                  config.define_queue(:test, test_task)

                  allow(Process).to receive(:setproctitle)

                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(persister: subprocess_persister))
                                               .and_call_original
                  allow_any_instance_of(QueueWorker).to receive(:work)

                  env.spawn_workers
               end

               it 'should provide the worker with a new task context' do
                  context = double('task context')

                  config.provide_context do
                     context
                  end
                  config.define_queue(:queue_name, test_task)

                  expect(QueueWorker).to receive(:new)
                                               .with(hash_including(task_context: context))
                                               .and_return(double('worker',
                                                                  work:      nil,
                                                                  start_log: nil,
                                                                  long_name: ''))

                  env.spawn_workers
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

                  env.spawn_workers
               end

               it 'should name each worker process with provided prefix' do
                  [:app1, :app2, :app3].each do |prefix|
                     config.define_queue(:test_queue, Test::Task::AllHooks)
                     config.prefix_processes(prefix)

                     allow_any_instance_of(QueueWorker).to receive(:work)

                     expect(Process).to receive(:setproctitle).with("#{prefix}-test_queue-queue-worker")

                     env.spawn_workers
                  end
               end

               it 'should tell the worker process to work' do
                  config.define_queue(:test1, Test::Task::AllHooks)
                  config.define_queue(:test2, Test::Task::AllHooks)
                  config.define_queue(:test3, Test::Task::AllHooks)

                  worker1 = double('worker1')
                  worker2 = double('worker2')
                  worker3 = double('worker3')

                  [worker1, worker2, worker3].each do |worker|
                     expect(worker).to receive(:work)

                     allow(worker).to receive(:start_log)
                     allow(worker).to receive(:long_name)
                  end

                  allow(QueueWorker).to receive(:new).and_return(worker1, worker2, worker3)

                  env.spawn_workers
               end

               it 'should NOT store any pids' do
                  env.spawn_workers

                  expect(env.processes).to be_empty
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
                  allow(env).to receive(:sleep)
                  allow(env).to receive(:loop) do |&block|
                     block.call
                  end

                  expect(Process).to receive(:kill).with(0, parent_pid)

                  env.spawn_workers

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
                  allow(env).to receive(:sleep)
                  allow(env).to receive(:loop) do |&block|
                     block.call
                  end

                  begin
                     env.spawn_workers
                  rescue SystemExit
                     # this is safer than stubbing exit, which can have weird consequences on the test system
                     exited = true
                  end

                  expect(exited).to be true
               end

               it 'should use a default log directory if not provided in setup' do
                  config.define_queue(:queue1, Test::Task::AllHooks)

                  allow_any_instance_of(QueueWorker).to receive(:work)

                  env.spawn_workers

                  expect(File.directory?('log/')).to be true
               end

               it 'should get each worker to start its log' do
                  config.define_queue(:queue1, test_task)
                  config.define_queue(:queue2, test_task)

                  config.log_in('some_dir/')

                  allow_any_instance_of(QueueWorker).to receive(:work)

                  env.spawn_workers

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
                  allow(env).to receive(:sleep)
                  allow(env).to receive(:loop) do |&block|
                     block.call
                  end

                  begin
                     env.spawn_workers
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

         describe '#act' do
            let(:persister) {double('persister', read_tasks: [], create_task: nil, update_task: nil, delete_task: nil)}

            let(:config) do
               config = Config.new
               config.load_with do
                  persister
               end
               config.define_queue(:test1, Test::Task::AllHooks)
               config.define_queue(:test2, Test::Task::AllHooks)
               config.define_queue(:test3, Test::Task::AllHooks)
               config
            end

            let(:env) {Environment.new(config)}

            before(:each) do
               config.enable_test_mode
               env.spawn_workers
            end

            it 'should call QueueWorker#act on every queue worker' do
               expect(env.queue_workers.size).to eq 3
               env.queue_workers.each do |worker|
                  expect(worker).to receive(:act)
               end

               env.act
            end

            it 'should call QueueWorker#act on queue worker for given queues only' do
               expect(env.queue_workers[0]).to_not receive(:act)
               expect(env.queue_workers[1]).to receive(:act)
               expect(env.queue_workers[2]).to receive(:act)

               env.act(:test2, :test3)
            end

            it 'should not complain when using Procrastinator.act in Test Mode' do
               expect {env.act}.to_not raise_error
            end

            it 'should complain if you try to use Procrastinator.act outside Test Mode' do
               config = Config.new
               config.load_with do
                  persister
               end

               non_test_env = Environment.new(config)

               err = <<~ERR
                  Procrastinator.act called outside Test Mode. 
                  Either use Procrastinator.spawn_workers or call #enable_test_mode in Procrastinator.setup.
               ERR

               expect {non_test_env.act}.to raise_error(RuntimeError,)
            end
         end
      end
   end
end