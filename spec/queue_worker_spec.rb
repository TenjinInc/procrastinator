# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe QueueWorker do
      let(:config) { Config.new }
      let(:persister) { double('loader', read: [], create: nil, update: nil, delete: nil) }
      let(:test_task) { Test::Task::AllHooks }
      let(:queue) { Procrastinator::Queue.new(name: :test_queue, task_class: test_task) }
      let(:instant_queue) { Procrastinator::Queue.new(name: :test_queue, task_class: test_task, update_period: 0) }

      describe '#initialize' do
         it 'should require a queue' do
            expect { QueueWorker.new(config: nil) }.to raise_error(ArgumentError, 'missing keyword: queue')
         end

         it 'should require a persister' do
            expect { QueueWorker.new(queue: nil) }.to raise_error(ArgumentError, 'missing keyword: config')
         end
      end

      describe '#work' do
         include FakeFS::SpecHelpers

         it 'should start a new log' do
            queue  = Procrastinator::Queue.new(name: :queue, task_class: test_task)
            worker = QueueWorker.new(queue: queue, config: Config.new)

            allow(worker).to receive(:loop) # stub loop

            expect(worker).to receive(:start_log)

            worker.work
         end

         it 'should wait for update_period' do
            [0.01, 0.02].each do |period|
               queue = Procrastinator::Queue.new(name:          :fast_queue,
                                                 task_class:    test_task,
                                                 update_period: period)

               worker = QueueWorker.new(queue: queue, config: Config.new)

               expect(worker).to receive(:loop) do |&block|
                  block.call
               end

               expect(worker).to receive(:sleep).with(period)

               worker.work
            end
         end

         it 'should cyclically call #act' do
            queue = Procrastinator::Queue.new(name:          :fast_queue,
                                              task_class:    test_task,
                                              update_period: 0.1)

            worker = QueueWorker.new(queue:  queue,
                                     config: Config.new)

            allow(worker).to receive(:sleep) # stub sleep

            n_loops = 3

            # control looping, otherwise infiniloop by design
            allow(worker).to receive(:loop) do |&block|
               n_loops.times { block.call }
            end

            expect(worker).to receive(:work_one).exactly(n_loops).times

            worker.work
         end

         it 'should log fatal errors from #act if logging' do
            FakeFS do
               queue = Procrastinator::Queue.new(name:          :test,
                                                 task_class:    test_task,
                                                 update_period: 0.1)

               config = Config.new
               config.log_with directory: 'log/'

               worker = QueueWorker.new(queue: queue, config: config)

               err = 'some fatal error'

               allow(worker).to receive(:sleep) # stub sleep

               # control looping, otherwise infiniloop by design
               allow(worker).to receive(:loop) do |&block|
                  block.call
               end

               allow(worker).to receive(:work_one).and_raise(err)

               worker.work

               log = File.read('log/test-queue-worker.log')

               expect(log).to include('F, ') # default fatal error notation in Ruby logger
               expect(log).to include(err)
            end
         end

         it 'should reraise fatal errors from #act if not logging' do
            queue = Procrastinator::Queue.new(name:          :fast_queue,
                                              task_class:    test_task,
                                              update_period: 0.1)

            config = Config.new
            config.log_with level: nil

            worker = QueueWorker.new(queue: queue, config: config)
            worker.start_log

            err = 'some fatal error'

            allow(worker).to receive(:sleep) # stub sleep

            # control looping, otherwise infiniloop by design
            allow(worker).to receive(:loop) do |&block|
               block.call
            end

            allow(worker).to receive(:work_one).and_raise(RuntimeError, err)

            expect do
               worker.work
            end.to raise_error(RuntimeError, err)
         end
      end

      describe '#work_one' do
         include FakeFS::SpecHelpers

         context 'loading and running tasks' do
            it 'should pass the given queue to its persister' do
               [:email, :cleanup].each do |name|
                  queue = Procrastinator::Queue.new(name:          name,
                                                    task_class:    test_task,
                                                    update_period: 0.01)

                  config = Config.new
                  config.load_with persister

                  worker = QueueWorker.new(queue: queue, config: config)

                  expect(persister).to receive(:read).with(queue: name)

                  worker.work_one
               end
            end

            it 'should always fetch the persister from config' do
               wrong_loader   = fake_persister([{id: 1}])
               correct_loader = fake_persister([{id: 2}])

               queue = Procrastinator::Queue.new(name:          :queueA,
                                                 task_class:    test_task,
                                                 update_period: 0.01)

               config = Config.new
               config.load_with wrong_loader

               worker = QueueWorker.new(queue: queue, config: config)

               config.load_with correct_loader

               expect(correct_loader).to receive(:read)
               expect(wrong_loader).to_not receive(:read)

               worker.work_one
            end

            it 'should sort tasks by run_at' do
               job1 = {id: 4, run_at: 1, initial_run_at: 0}
               job2 = {id: 5, run_at: 2, initial_run_at: 0}
               job3 = {id: 6, run_at: 3, initial_run_at: 0}

               handler1 = Test::Task::AllHooks.new
               handler2 = Test::Task::AllHooks.new
               handler3 = Test::Task::AllHooks.new

               allow(Test::Task::AllHooks).to receive(:new).and_return(handler1, handler2, handler3)

               persister = double('disorganized persister',
                                  read:   [job2, job1, job3],
                                  create: nil,
                                  update: nil,
                                  delete: nil)

               config = Config.new
               config.load_with persister

               worker = QueueWorker.new(queue: instant_queue, config: config)

               expect(handler1).to receive(:run)

               worker.work_one
            end

            it 'should ignore tasks with nil run_at' do
               task1 = Test::Task::AllHooks.new
               task2 = Test::Task::AllHooks.new

               job1 = {id: 4, run_at: nil, initial_run_at: 0}
               job2 = {id: 5, run_at: 2, initial_run_at: 0}

               allow(Test::Task::AllHooks).to receive(:new).and_return(task2)

               persister = double('disorganized persister',
                                  read:   [job2, job1],
                                  create: nil,
                                  update: nil,
                                  delete: nil)

               config.load_with persister

               worker = QueueWorker.new(queue: instant_queue, config: config)

               expect(task1).to_not receive(:run)
               expect(task2).to receive(:run)

               worker.work_one
            end

            it 'should reload tasks every cycle' do
               task1 = double('task1')
               task2 = double('task2')

               task1_duration = 4
               task2_duration = 6

               allow(task1).to receive(:run) do
                  Timecop.travel(task1_duration)
               end
               allow(task2).to receive(:run) do
                  Timecop.travel(task2_duration)
               end

               job1 = {run_at: 1}
               job2 = {run_at: 1}

               config.load_with persister

               allow(persister).to receive(:read).and_return([job1], [job2])

               allow(Test::Task::AllHooks).to receive(:new).and_return(task1, task2)

               start_time = Time.now

               Timecop.freeze(start_time) do
                  worker = QueueWorker.new(queue: instant_queue, config: config)

                  worker.work_one
                  worker.work_one

                  expect(Time.now.to_i).to eq start_time.to_i + task1_duration + task2_duration
               end
            end

            it 'should populate the data into a Task' do
               task_data = {
                     id:             double('id'),
                     run_at:         double('run_at', to_i: 1),
                     initial_run_at: double('initial', to_i: 1),
                     expire_at:      double('expiry', to_i: 1),
                     attempts:       0,
                     last_error:     double('last error'),
                     last_fail_at:   double('last fail at'),
                     data:           YAML.dump(%w[some data])
               }

               expect(TaskMetaData).to receive(:new).with(task_data).and_call_original

               config.load_with fake_persister([task_data])

               worker = QueueWorker.new(queue: instant_queue, config: config)

               worker.work_one
            end

            it 'should convert the read results to hash' do
               task_data = double('data struct',
                                  to_h: {
                                        id:             double('id'),
                                        run_at:         double('run_at', to_i: 1),
                                        initial_run_at: double('initial', to_i: 1),
                                        expire_at:      double('expiry', to_i: 1),
                                        attempts:       0,
                                        last_error:     double('last error'),
                                        last_fail_at:   double('last fail at'),
                                        data:           YAML.dump(%w[some data])
                                  })

               expect(TaskMetaData).to receive(:new).with(task_data.to_h).and_call_original

               config.load_with fake_persister([task_data])

               worker = QueueWorker.new(queue: instant_queue, config: config)

               worker.work_one
            end

            it 'should ignore any unused or unknown data' do
               task_data = {id:     1,
                            queue:  double('queue'),
                            run_at: double('run_at', to_i: 2),
                            bogus:  double('bogus')}

               expect(TaskMetaData).to receive(:new)
                                             .with(id:     task_data[:id],
                                                   run_at: task_data[:run_at])
                                             .and_call_original

               config.load_with fake_persister([task_data])

               worker = QueueWorker.new(queue: instant_queue, config: config)

               worker.work_one
            end

            it 'should run a TaskWorker with the task metadata' do
               task_data = {run_at: 1}

               meta = TaskMetaData.new(task_data)
               allow(TaskMetaData).to receive(:new).and_return(meta)

               expect(TaskWorker).to receive(:new).with(hash_including(metadata: meta)).and_call_original

               config.load_with fake_persister([task_data])

               worker = QueueWorker.new(queue: instant_queue, config: config)

               worker.work_one
            end

            it 'should pass the TaskWorker the task context' do
               task_data = {run_at: 1}
               context   = double('context object')

               expect(TaskWorker).to receive(:new).with(hash_including(context: context)).and_call_original

               config.load_with fake_persister([task_data])
               config.provide_context context

               worker = QueueWorker.new(queue: instant_queue, config: config)

               worker.work_one
            end

            it 'should pass the TaskWorker the queue settings' do
               expect(TaskWorker).to receive(:new).with(hash_including(queue: instant_queue)).and_call_original

               config.load_with fake_persister([{run_at: 1}])

               worker = QueueWorker.new(queue: instant_queue, config: config)

               worker.work_one
            end

            it 'should pass the TaskWorker the scheduler' do
               expect(TaskWorker).to receive(:new).with(hash_including(scheduler: an_instance_of(Scheduler))).and_call_original

               config.load_with fake_persister([{run_at: 1}])

               worker = QueueWorker.new(queue: instant_queue, config: config)

               worker.work_one
            end

            it 'should pass the TaskWorker the logger if log directory given' do
               logger = Logger.new(StringIO.new)

               allow(Logger).to receive(:new).and_return(logger)
               expect(TaskWorker).to receive(:new).with(hash_including(logger: logger)).and_call_original

               config.load_with fake_persister([{run_at: 1}])
               config.log_with directory: '/log'

               FakeFS do
                  worker = QueueWorker.new(queue: instant_queue, config: config)
                  worker.start_log

                  worker.work_one
               end
            end

            it 'should run a TaskWorker for the first ready task' do
               task_data1 = {run_at: 1}
               task_data2 = {run_at: 1}
               task_data3 = {run_at: 1}

               expect(TaskWorker).to receive(:new).once.and_call_original

               config.load_with fake_persister([task_data1, task_data2, task_data3])

               worker = QueueWorker.new(queue: instant_queue, config: config)

               worker.work_one
            end

            it 'should not start any TaskWorkers for unready tasks' do
               now = Time.now

               task_data1 = {run_at: now}
               task_data2 = {run_at: now + 1}

               expect(TaskWorker).to receive(:new).ordered.and_call_original
               expect(TaskWorker).to_not receive(:new).ordered.and_call_original

               config.load_with fake_persister([task_data1, task_data2])

               worker = QueueWorker.new(queue: instant_queue, config: config)

               Timecop.freeze(now) do
                  worker.work_one
               end
            end
         end

         context 'TaskWorker succeeds' do
            it 'should delete the task' do
               task_data = {
                     id:     double('id'),
                     run_at: 0
               }

               allow(persister).to receive(:read).and_return([task_data])

               config.load_with persister

               worker = QueueWorker.new(queue: instant_queue, config: config)

               expect(persister).to receive(:delete).with(task_data[:id])

               worker.work_one
            end
         end

         context 'TaskWorker fails for fails For The Last Time' do
            # to do:
            # it 'should promote Captain Piett to Admiral Piett'

            it 'should update the task' do
               {queueA: 0, queueB: 1}.each do |name, max_attempts|
                  id        = double('id')
                  task_data = {
                        id:     id,
                        run_at: 0
                  }

                  persister = fake_persister([task_data])

                  config.load_with persister

                  # allow_any_instance_of(TaskWorker).to receive(:to_h).and_return(task_hash)

                  queue = Procrastinator::Queue.new(name:          name,
                                                    task_class:    Test::Task::Fail,
                                                    update_period: 0,
                                                    max_attempts:  max_attempts)

                  worker = QueueWorker.new(queue: queue, config: config)

                  expect(persister).to receive(:update).with(id, hash_including(id:     id,
                                                                                run_at: nil,
                                                                                queue:  name.to_s))

                  worker.work_one
               end
            end
         end
      end

      describe '#start_log' do
         include FakeFS::SpecHelpers

         before(:each) do
            FakeFS.clear! if FakeFS.activated?
         end

         context 'no_log' do
            before(:each) do
               config.log_with level: nil
            end

            it 'should NOT create the log directory' do
               worker = QueueWorker.new(queue: queue, config: config)

               worker.start_log

               expect(Dir.glob('/*')).to be_empty
            end

            it 'should NOT create a logger instance for this worker' do
               worker = QueueWorker.new(queue: queue, config: config)

               expect(Logger).to_not receive(:new)

               worker.start_log
            end

            it 'should NOT create a log file for this worker' do
               queue = Procrastinator::Queue.new(name:       :queue1,
                                                 task_class: Test::Task::AllHooks)

               worker = QueueWorker.new(queue: queue, config: config)

               worker.start_log

               expect(File.file?('/queue1-queue-worker.log')).to be false
            end
         end

         context 'logging directory provided' do
            before(:each) do
               config.log_with directory: 'some_dir/'
            end

            it 'should create the log directory if it does not exist' do
               worker = QueueWorker.new(queue: queue, config: config)

               worker.start_log

               expect(File.directory?('some_dir/')).to be true
            end

            it 'should log starting a queue worker' do
               [{parent: 10, child: 2000, queues: :test1},
                {parent: 30, child: 4000, queues: :test2}].each do |pid_hash|
                  parent_pid = pid_hash[:parent]
                  child_pid  = pid_hash[:child]
                  queue_name = pid_hash[:queues]

                  queue = Procrastinator::Queue.new(name:       queue_name,
                                                    task_class: Test::Task::AllHooks)

                  worker = QueueWorker.new(queue: queue, config: config)

                  allow(Process).to receive(:ppid).and_return(parent_pid)
                  allow(Process).to receive(:pid).and_return(child_pid)

                  worker.start_log

                  log_path = "some_dir/#{ worker.long_name }.log"

                  log_contents = File.read(log_path)

                  expect(log_contents).to include("Started worker thread to consume queue: #{ queue_name }")
               end
            end

            it 'should append to the log file if it already exists' do
               log_dir = 'a/log/directory'

               config.log_with directory: log_dir

               worker = QueueWorker.new(queue: queue, config: config)

               log_path = "#{ log_dir }/#{ worker.long_name }.log"

               existing_data = 'abcdef'

               FileUtils.mkdir_p(log_dir)
               File.open(log_path, 'a+') do |f|
                  f.write existing_data
               end

               worker.start_log

               expect(File.read(log_path)).to include(existing_data)
            end

            it 'should log at the provided level' do
               logger = Logger.new(StringIO.new)

               Logger::Severity.constants.each do |level|
                  worker = QueueWorker.new(queue: queue, config: config)

                  config.log_with level: level

                  expect(Logger).to receive(:new).with(anything, anything, anything, hash_including(level: level))
                                                 .and_return logger

                  worker.start_log
               end
            end

            it 'should not start a new logger if there is a logger defined' do
               worker = QueueWorker.new(queue: queue, config: config)

               worker.start_log

               expect(Logger).to_not receive(:new)

               worker.start_log
            end

            it 'should include the queue name in the log output' do
               worker = QueueWorker.new(queue: queue, config: config)

               worker.start_log

               queue_name = :test_queue

               queue = Procrastinator::Queue.new(name:       queue_name,
                                                 task_class: Test::Task::AllHooks)

               worker = QueueWorker.new(queue: queue, config: config)

               allow(Process).to receive(:ppid).and_return(1)
               allow(Process).to receive(:pid).and_return(2)

               worker.start_log

               log_path = "some_dir/#{ worker.long_name }.log"

               log_contents = File.read(log_path)

               expect(log_contents).to include("-- #{ worker.long_name }:")
            end

            it 'should use the provided shift age and size' do
               logger = Logger.new(StringIO.new)

               size = double('size')
               age  = double('age')
               config.log_with(shift_size: size, shift_age: age)

               worker = QueueWorker.new(queue: queue, config: config)

               expect(Logger).to receive(:new).with(anything, age, size, anything).and_return(logger)

               worker.start_log
            end
         end
      end
   end
end
