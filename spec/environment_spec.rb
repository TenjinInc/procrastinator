require 'spec_helper'

module Procrastinator
   describe Environment do
      describe '#initialize' do
         it 'should require that the persister not be nil' do
            expect { Environment.new(nil, email: {}) }.to raise_error(ArgumentError, 'persister cannot be nil')
         end

         it 'should require that the queue definitions not be nil' do
            expect { Environment.new(double('persister'), nil) }.to raise_error(ArgumentError, 'queue definitions cannot be nil')
         end

         it 'should require that the queue definitions have at least one element' do
            expect { Environment.new(double('persister'), {}) }.to raise_error(ArgumentError, 'queue definition hash is empty')
         end

         it 'should require the persister respond to #read_tasks' do
            expect do
               Environment.new(double('persister', create_task: nil, update_task: nil, delete_task: nil), email: {})
            end.to raise_error(MalformedPersisterError, 'persister must repond to #read_tasks')
         end

         it 'should require the persister respond to #create_task' do
            expect do
               Environment.new(double('persister', read_tasks: nil, update_task: nil, delete_task: nil), email: {})
            end.to raise_error(MalformedPersisterError, 'persister must repond to #create_task')
         end

         it 'should require the persister respond to #update_task' do
            expect do
               Environment.new(double('persister', read_tasks: nil, create_task: nil, delete_task: nil), email: {})
            end.to raise_error(MalformedPersisterError, 'persister must repond to #update_task')
         end

         it 'should require the persister respond to #delete_task' do
            expect do
               Environment.new(double('persister', read_tasks: nil, create_task: nil, update_task: nil), email: {})
            end.to raise_error(MalformedPersisterError, 'persister must repond to #delete_task')
         end
      end

      describe '#delay' do
         # TODO: Procrastinator.setup(task_repo, email:   {timeout: 1.hour, max_attempts: 15, max_tasks: 5},
         # TODO:                                 cleanup: {timeout: 1.minute, max_attempts: 3, max_tasks: 2} )
         let(:procrastinator) { instance_double(Environment) }

         let(:persister) { double('persister', read_tasks: [], create_task: nil, update_task: nil, delete_task: nil) }
         let(:env) { Environment.new(persister, queue1: {}) }
         let(:task) { double('task', run: nil) }

         # TODO: api: Procrastinator.delay(run_at: Time.now + 10, queue: :email, SendInvitation.new(to: 'bob@example.com'))

         it 'should record a task on the given queue' do
            # these are, at the moment, all of the arguments the dev can pass in
            expect(persister).to receive(:create_task).with(include(queue: :queue1))

            env.delay(queue: :queue1, task: task)
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

         it 'should require task not be nil' do
            expect { env.delay(task: nil) }.to raise_error(ArgumentError, 'task may not be nil')
         end

         it 'should complain if task does not support #run' do
            expect do
               env.delay(task: double('bad_task'))
            end.to raise_error(MalformedTaskError, 'given task does not support #run method')
         end

         it 'should require queue be provided if there is more than one queue defined' do
            env = Environment.new(persister, queue1: {}, queue2: {})

            expect { env.delay(run_at: 0, task: task) }.to raise_error(ArgumentError, 'queue must be specified when more than one is registered')

            # also test the negative
            expect { env.delay(queue: :queue1, run_at: 0, task: task) }.to_not raise_error
         end

         it 'should not require queue be provided if there only one queue defined' do
            env = Environment.new(persister, queue1: {})

            expect { env.delay(run_at: 0, task: task) }.to_not raise_error
         end

         it 'should complain when the given queue is not registered' do
            [:bogus, :other_bogus].each do |name|
               expect { env.delay(queue: name, run_at: 0, task: task) }.to raise_error(ArgumentError, %Q{there is no "#{name}" queue registered in this environment})
            end
         end
      end
      describe 'spawn_workers' do
         let(:persister) { double('persister', read_tasks: [], create_task: [], update_task: [], delete_task: []) }
         let(:queues) { {testa: {}, testb: {}, testc: {}} }

         context 'parent process' do
            before(:each) { allow(Process).to receive(:setproctitle) }

            it 'should fork a worker process for each queue' do
               [{test1: {}}, {test2a: {}, test2b: {}, test2c: {}}].each do |queues|
                  env = Environment.new(persister, queues)

                  expect(env).to receive(:fork).exactly(queues.size).times

                  env.spawn_workers
               end
            end

            it 'should not wait for the QueueWorker' do
               Timeout::timeout(1) do
                  env  = Environment.new(persister, queues)
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
               env = Environment.new(persister, queues)

               allow(env).to receive(:fork) do |&block|
                  block.call
                  nil
               end
               allow(Process).to receive(:setproctitle)

               queues.each do |name, props|
                  expect(QueueWorker).to receive(:new).with(props.merge(persister: persister, name: name)).and_return(double('worker', work: nil))
               end

               env.spawn_workers
            end

            it 'should tell the worker process to work' do
               env = Environment.new(persister, queues)

               allow(env).to receive(:fork) do |&block|
                  block.call
                  1
               end

               worker1 = double('worker1')
               worker2 = double('worker2')
               worker3 = double('worker3')

               allow(QueueWorker).to receive(:new).and_return(worker1, worker2, worker3)

               expect(worker1).to receive(:work)
               expect(worker2).to receive(:work)
               expect(worker3).to receive(:work)

               env.spawn_workers
            end

            it 'should record its spawned processes' do
               env = Environment.new(persister, queues)

               pid1 = 10
               pid2 = 11
               pid3 = 12

               allow(env).to receive(:fork).and_return(pid1, pid2, pid3)

               env.spawn_workers

               expect(env.processes).to eq [pid1, pid2, pid3]
            end
         end

         context 'subprocess' do
            before(:each) { allow(Process).to receive(:setproctitle) }

            def stub_fork(receiver)
               allow(receiver).to receive(:fork) do |&block|
                  block.call
                  nil
               end
            end

            it 'should name each worker process' do
               [{test1: {}}, {test2a: {}, test2b: {}, test2c: {}}].each do |queues|
                  env = Environment.new(persister, queues)

                  stub_fork(env)

                  allow_any_instance_of(QueueWorker).to receive(:work)

                  queues.each do |name, props|
                     expect(Process).to receive(:setproctitle).with("#{name}-queue-worker")
                  end

                  env.spawn_workers
               end
            end

            it 'should exit if the parent process dies' do
               exited = false

               begin
                  env = Environment.new(persister, queues)

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