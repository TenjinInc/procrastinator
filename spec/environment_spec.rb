require 'spec_helper'

module Procrastinator
   describe Environment do
      describe '#initialize' do
         it 'should require that the persister NOT be nil' do
            expect { Environment.new(persister: nil) }.to raise_error(ArgumentError, 'persister cannot be nil')
         end

         it 'should require the persister respond to #read_tasks' do
            expect do
               Environment.new(persister: double('persister', create_task: nil, update_task: nil, delete_task: nil))
            end.to raise_error(MalformedPersisterError, 'persister must repond to #read_tasks')
         end

         it 'should require the persister respond to #create_task' do
            expect do
               Environment.new(persister: double('persister', read_tasks: nil, update_task: nil, delete_task: nil))
            end.to raise_error(MalformedPersisterError, 'persister must repond to #create_task')
         end

         it 'should require the persister respond to #update_task' do
            expect do
               Environment.new(persister: double('persister', read_tasks: nil, create_task: nil, delete_task: nil))
            end.to raise_error(MalformedPersisterError, 'persister must repond to #update_task')
         end

         it 'should require the persister respond to #delete_task' do
            expect do
               Environment.new(persister: double('persister', read_tasks: nil, create_task: nil, update_task: nil))
            end.to raise_error(MalformedPersisterError, 'persister must repond to #delete_task')
         end
      end

      describe '#define_queue' do
         let(:persister) { double('persister', read_tasks: [], create_task: nil, update_task: nil, delete_task: nil) }
         let(:env) { Environment.new(persister: persister) }

         it 'should require that the queue definitions NOT be nil' do
            expect { env.define_queue(nil) }.to raise_error(ArgumentError, 'queue name cannot be nil')
         end

         it 'should add a queue with its timeout, max_tasks, max_attempts, update_period' do
            hash = {}

            (1..3).each do |i|
               attrs = {timeout: i, max_tasks: i+1, max_attempts: i+2, update_period: i+3}

               env.define_queue("queue#{i}", attrs)

               hash["queue#{i}"] = attrs

               expect(env.queue_definitions).to eq hash
            end
         end
      end

      describe '#delay' do
         # api: Procrastinator.delay(run_at: Time.now + 10, queue: :email, SendInvitation.new(to: 'bob@example.com'))

         let(:persister) { double('persister', read_tasks: [], create_task: nil, update_task: nil, delete_task: nil) }
         let(:env) { Environment.new(persister: persister) }
         let(:task) { double('task', run: nil) }

         before(:each) do
            env.define_queue(:test)
         end

         it 'should record a task on the given queue' do
            [:queue1, :queue2].each do |queue_name|
               expect(persister).to receive(:create_task).with(include(queue: queue_name))

               env.define_queue(queue_name)

               env.delay(queue: queue_name, task: task)
            end
         end

         it 'should record a task with given run_at and expire_at' do
            run_stamp    = double('runstamp')
            expire_stamp = double('expirestamp')

            # these are, at the moment, all of the arguments the dev can pass in
            args         = {run_at: double('run', to_i: run_stamp), expire_at: double('expire', to_i: expire_stamp)}

            expect(persister).to receive(:create_task).with(include(run_at: run_stamp, expire_at: expire_stamp))

            env.delay(args.merge(task: task))
         end

         it 'should record a task with serialized task strategy' do
            # these are, at the moment, all of the arguments the dev can pass in
            expect(persister).to receive(:create_task).with(include(task: YAML.dump(task)))

            env.delay(task: task)
         end

         it 'should default run_at to now' do
            now = Time.now

            Timecop.freeze(now) do
               expect(persister).to receive(:create_task).with(include(run_at: now.to_i))

               env.delay(task: task)
            end
         end

         it 'should record initial_run_at and run_at to be the same' do
            time = Time.now

            expect(persister).to receive(:create_task).with(include(run_at: time.to_i, initial_run_at: time.to_i))

            env.delay(run_at: time, task: task)
         end

         it 'should record convert run_at, initial_run_at, expire_at to ints' do
            expect(persister).to receive(:create_task).with(include(run_at: 0, initial_run_at: 0, expire_at: 1))

            env.delay(run_at:    double('time', to_i: 0),
                      expire_at: double('time', to_i: 1),
                      task:      task)
         end

         it 'should default expire_at to nil' do
            expect(persister).to receive(:create_task).with(include(expire_at: nil))

            env.delay(task: task)
         end

         it 'should require a task be given' do
            expect { env.delay }.to raise_error(ArgumentError, 'missing keyword: task')
         end

         it 'should require task NOT be nil' do
            expect { env.delay(task: nil) }.to raise_error(ArgumentError, 'task may not be nil')
         end

         it 'should complain if task does NOT support #run' do
            expect do
               env.delay(task: double('bad_task'))
            end.to raise_error(MalformedTaskError, 'the provided task does not support #run method')
         end

         it 'should NOT complain about well-formed hooks' do
            [:success, :fail, :final_fail].each do |method|
               task = GoodTask.new

               # allow(task).to receive(method).with('')

               expect do
                  env.delay(task: task)
               end.to_not raise_error
            end
         end

         it 'should complain if task does NOT accept a parameter to #success' do
            task = double('bad_task', run: nil)

            allow(task).to receive(:success) do
            end

            expect do
               env.delay(task: task)
            end.to raise_error(MalformedTaskError, 'the provided task must accept a parameter to its #success method')
         end

         it 'should complain if task does NOT accept a parameter to #fail' do
            task = double('bad_task', run: nil)

            allow(task).to receive(:fail) do
            end

            expect do
               env.delay(task: task)
            end.to raise_error(MalformedTaskError, 'the provided task must accept a parameter to its #fail method')
         end

         it 'should complain if task does NOT accept a parameter to #final_fail' do
            task = double('bad_task', run: nil)

            allow(task).to receive(:final_fail) do
            end

            expect do
               env.delay(task: task)
            end.to raise_error(MalformedTaskError, 'the provided task must accept a parameter to its #final_fail method')
         end

         it 'should require queue be provided if there is more than one queue defined' do
            env.define_queue(:queue1)
            env.define_queue(:queue2)

            expect { env.delay(run_at: 0, task: task) }.to raise_error(ArgumentError, 'queue must be specified when more than one is registered. Defined queues are: :test, :queue1, :queue2')

            # also test the negative
            expect { env.delay(queue: :queue1, run_at: 0, task: task) }.to_not raise_error
         end

         it 'should NOT require queue be provided if there only one queue defined' do
            env = Environment.new(persister: persister)
            env.define_queue(:queue)

            expect { env.delay(run_at: 0, task: task) }.to_not raise_error
         end

         it 'should assume the queue if there only one queue defined' do
            env = Environment.new(persister: persister)
            env.define_queue(:some_queue)

            expect(persister).to receive(:create_task).with(include(queue: :some_queue))

            env.delay(task: task)
         end

         it 'should complain when the given queue is not registered' do
            [:bogus, :other_bogus].each do |name|
               expect { env.delay(queue: name, run_at: 0, task: task) }.to raise_error(ArgumentError, %Q{there is no "#{name}" queue registered in this environment})
            end
         end
      end

      describe 'spawn_workers' do
         let(:persister) { double('persister', read_tasks: [], create_task: [], update_task: [], delete_task: []) }
         let(:env) { Environment.new(persister: persister) }

         context 'test mode enabled' do
            let(:env) { Environment.new(persister: persister, test_mode: true) }

            it 'should create a worker for each queue definition' do
               queue_defs = {test2a: {max_tasks: 1}, test2b: {max_tasks: 2}, test2c: {max_tasks: 3}}
               queue_defs.each do |name, props|
                  env.define_queue(name, props)
               end

               queue_defs.each do |name, props|
                  expect(QueueWorker).to receive(:new).with(props.merge(persister: persister, name: name)).and_return(double('worker', work: nil))
               end

               env.spawn_workers
            end

            it 'should not fork' do
               env.define_queue(:test)

               expect(env).to_not receive(:fork)

               env.spawn_workers
            end

            it 'should not call #work' do
               env.define_queue(:test)

               expect_any_instance_of(QueueWorker).to_not receive(:work)

               env.spawn_workers
            end

            it 'should NOT change the process title' do
               env.define_queue(:test)

               stub_fork(env)
               expect(Process).to_not receive(:setproctitle)

               env.spawn_workers
            end

            it 'should NOT open a log file'
         end

         context 'test mode disabled' do
            context 'parent process' do
               before(:each) { allow(Process).to receive(:setproctitle) }

               it 'should fork a worker process' do
                  env.define_queue(:test)

                  expect(env).to receive(:fork).once

                  env.spawn_workers
               end

               it 'should fork a worker process for each queue' do
                  queue_defs = {test2a: {}, test2b: {}, test2c: {}}
                  queue_defs.each do |name, props|
                     env.define_queue(name, props)
                  end

                  expect(env).to receive(:fork).exactly(queue_defs.size).times

                  env.spawn_workers
               end

               it 'should not wait for the QueueWorker' do
                  env.define_queue(:test1)
                  env.define_queue(:test2)
                  env.define_queue(:test3)

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

               it 'should create a QueueWorker in each subprocess' do
                  queue_defs = {test2a: {}, test2b: {}, test2c: {}}

                  allow(env).to receive(:fork) do |&block|
                     block.call
                     nil
                  end
                  allow(Process).to receive(:setproctitle)

                  queue_defs.each do |name, props|
                     env.define_queue(name, props)

                     expect(QueueWorker).to receive(:new).with(props.merge(persister: persister, name: name)).and_return(double('worker', work: nil))
                  end

                  env.spawn_workers
               end

               it 'should tell the worker process to work' do
                  allow(env).to receive(:fork) do |&block|
                     block.call
                     1
                  end

                  env.define_queue(:test1)
                  env.define_queue(:test2)
                  env.define_queue(:test3)

                  worker1 = double('worker1')
                  worker2 = double('worker2')
                  worker3 = double('worker3')

                  expect(worker1).to receive(:work)
                  expect(worker2).to receive(:work)
                  expect(worker3).to receive(:work)

                  allow(QueueWorker).to receive(:new).and_return(worker1, worker2, worker3)

                  env.spawn_workers
               end

               it 'should record its spawned processes' do
                  env.define_queue(:test1)
                  env.define_queue(:test2)
                  env.define_queue(:test3)

                  pid1 = 10
                  pid2 = 11
                  pid3 = 12

                  allow(env).to receive(:fork).and_return(pid1, pid2, pid3)

                  env.spawn_workers

                  expect(env.processes).to eq [pid1, pid2, pid3]
               end

               it 'should store the PID of children in the ENV'
            end

            context 'subprocess' do
               before(:each) { allow(Process).to receive(:setproctitle) }

               it 'should name each worker process' do
                  queues = [:test1, :test2, :test3]
                  queues.each do |name|
                     env.define_queue(name)
                  end

                  stub_fork(env)

                  allow_any_instance_of(QueueWorker).to receive(:work)

                  queues.each do |name|
                     expect(Process).to receive(:setproctitle).with("#{name}-queue-worker")
                  end

                  env.spawn_workers
               end

               it 'should exit if the parent process dies' do
                  exited = false

                  begin
                     env = Environment.new(persister: persister)
                     env.define_queue(:test)

                     stub_fork(env)

                     allow(Thread).to receive(:new) do |&block|
                        begin
                           block.call(-2)
                        rescue Errno::ESRCH
                           exit
                        end
                     end

                     env.spawn_workers
                  rescue SystemExit
                     # this is safer than stubbing exit, which can have weird consequences
                     exited = true
                  end

                  expect(exited).to be true
               end

               it 'should create a log file if it does NOT exist' # named after the queue

               it 'should create the log directory if it does NOT exist'

               it 'should append to the log file if it already exists'

               it 'should log exiting when parent process dies'

               it 'should provide default logging location' # ./log/
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
         let(:persister) { double('persister', read_tasks: [], create_task: nil, update_task: nil, delete_task: nil) }

         let(:env) do
            env = Environment.new(persister: persister, test_mode: true)
            env.define_queue(:test1)
            env.define_queue(:test2)
            env.define_queue(:test3)
            env.spawn_workers
            env
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
            test_env = Environment.new(persister: persister, test_mode: true)

            expect { test_env.act }.to_not raise_error
         end

         it 'should complain if you try to use Procrastinator.act outside Test Mode' do
            non_test_env = Environment.new(persister: persister, test_mode: false)

            expect { non_test_env.act }.to raise_error(RuntimeError, 'Procrastinator.act called outside Test Mode. Enable test mode by setting Procrastinator.test_mode = true before running setup')
         end
      end
   end
end