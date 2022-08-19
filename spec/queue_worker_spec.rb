# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe QueueWorker do
      let(:persister) { double('task store', read: [], create: nil, update: nil, delete: nil) }
      let(:test_task) { Test::Task::AllHooks }

      describe '#initialize' do
         let(:config) do
            Config.new do |config|
               config.define_queue(:emails, test_task)
               config.define_queue(:reminders, test_task)
            end
         end

         it 'should require a queue keyword argument' do
            expect { QueueWorker.new(config: nil) }.to raise_error(ArgumentError, 'missing keyword: queue')
         end

         it 'should require queue not be nil' do
            expect { QueueWorker.new(queue: nil, config: nil) }.to raise_error(ArgumentError, ':queue cannot be nil')
         end

         it 'should require a config keyword argument' do
            expect { QueueWorker.new(queue: nil) }.to raise_error(ArgumentError, 'missing keyword: config')
         end

         it 'should require the config argument not be nil' do
            expect { QueueWorker.new(queue: config.queues.first, config: nil) }.to raise_error(ArgumentError, ':config cannot be nil')
         end

         it 'should accept a queue name instead of a queue object' do
            config = Config.new do |c|
               c.define_queue(:some_queue, test_task)
            end

            worker = QueueWorker.new(queue: :some_queue, config: config)

            expect(worker.name).to eq :some_queue
         end

         # TOOD: would be nice if this was frozen, too.
         # it 'should freeze itself' do
         #    worker = QueueWorker.new(queue: config.queues.first, config: config)
         #
         #    expect(worker).to be_frozen
         # end
      end

      describe '#work' do
         include FakeFS::SpecHelpers

         let(:config) do
            Config.new do |c|
               c.define_queue(:fast_queue, test_task, update_period: 0.01)
            end
         end

         # this needs to be here and not in init because work is called in sub threads / daemon,
         # but init is called in the parent booting process
         it 'should start a new log' do
            worker = QueueWorker.new(queue: :fast_queue, config: config)

            allow(worker).to receive(:loop) # stub infiniloop

            expect(worker).to receive(:open_log!).and_call_original

            worker.work
         end

         it 'should wait for update_period' do
            [0.01, 0.02].each do |period|
               config = Config.new do |c|
                  c.define_queue(:fast_queue, test_task, update_period: period)
               end

               worker = QueueWorker.new(queue: :fast_queue, config: config)

               expect(worker).to receive(:loop) do |&block|
                  block.call
               end

               expect(worker).to receive(:sleep).with(period)

               worker.work
            end
         end

         it 'should cyclically call #work_one' do
            worker = QueueWorker.new(queue:  :fast_queue,
                                     config: config)

            allow(worker).to receive(:sleep) # stub sleep

            n_loops = 3

            # control looping, otherwise infiniloop by design
            allow(worker).to receive(:loop) do |&block|
               n_loops.times { block.call }
            end

            expect(worker).to receive(:work_one).exactly(n_loops).times

            worker.work
         end

         it 'should pass the TaskWorker the logger' do
            logger = Logger.new(StringIO.new)

            allow(Logger).to receive(:new).and_return(logger)

            config = Config.new do |c|
               c.define_queue(:fast_queue, test_task, update_period: 0, store: fake_persister([{run_at: 1}]))
            end

            expect(TaskWorker).to receive(:new).with(hash_including(logger: logger)).and_call_original
            worker = QueueWorker.new(queue: :fast_queue, config: config)
            allow(worker).to receive(:loop).and_yield

            worker.work
         end

         it 'should log starting a queue worker' do
            [:test1, :test2].each do |queue_name|
               config = Config.new do |c|
                  c.define_queue(queue_name, test_task, update_period: 0, store: persister)
               end

               worker = QueueWorker.new(queue: queue_name, config: config)
               allow(worker).to receive(:loop).and_yield
               worker.work

               log_contents = Pathname.new("log/#{ queue_name }-queue-worker.log").read

               expect(log_contents).to include("Started worker thread to consume queue: #{ queue_name }")
            end
         end

         it 'should log fatal errors from #work_one if logging' do
            worker = QueueWorker.new(queue: :fast_queue, config: config)

            err = 'some fatal error'

            allow(worker).to receive(:sleep) # stub sleep

            # control looping, otherwise infiniloop by design
            allow(worker).to receive(:loop) do |&block|
               block.call
            end

            allow(worker).to receive(:work_one).and_raise(err)

            worker.work

            log = File.read('log/fast_queue-queue-worker.log')

            expect(log).to include('F, ') # default fatal error notation in Ruby logger
            expect(log).to include(err)
         end

         it 'should reraise fatal errors from #work_one if logging disabled' do
            config = Config.new do |c|
               c.define_queue :fast_queue, test_task, update_period: 0.1
               c.log_with level: nil
            end

            worker = QueueWorker.new(queue: config.queues.first, config: config)
            worker.open_log!('fast_queue-worker', config)

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

         let(:config) do
            Config.new do |c|
               c.with_store(persister) do
                  c.define_queue(:email, test_task, update_period: 0.01)
                  c.define_queue(:cleanup, test_task, update_period: 0.01)
               end
            end
         end

         context 'loading and running tasks' do
            it 'should pass the given queue to its persister' do
               config.queues.each do |queue|
                  worker = QueueWorker.new(queue: queue, config: config)

                  expect(persister).to receive(:read).with(queue: queue.name)

                  worker.work_one
               end
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

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: persister)
               end

               worker = QueueWorker.new(queue: config.queues.first, config: config)

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

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: persister)
               end

               worker = QueueWorker.new(queue: config.queues.first, config: config)

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

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: persister)
               end

               allow(persister).to receive(:read).and_return([job1], [job2])

               allow(Test::Task::AllHooks).to receive(:new).and_return(task1, task2)

               start_time = Time.now

               Timecop.freeze(start_time) do
                  worker = QueueWorker.new(queue: config.queues.first, config: config)

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
                     data:           '{"some data": 5}'
               }

               expect(TaskMetaData).to receive(:new).with(task_data).and_call_original

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: fake_persister([task_data]))
               end

               worker = QueueWorker.new(queue: config.queues.first, config: config)

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
                                        data:           '{"some data": 5}'
                                  })

               expect(TaskMetaData).to receive(:new).with(task_data.to_h).and_call_original

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: fake_persister([task_data]))
               end

               worker = QueueWorker.new(queue: config.queues.first, config: config)

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

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: fake_persister([task_data]))
               end

               worker = QueueWorker.new(queue: config.queues.first, config: config)

               worker.work_one
            end

            it 'should run a TaskWorker with the task metadata' do
               task_data = {run_at: 1}

               meta = TaskMetaData.new(task_data)
               allow(TaskMetaData).to receive(:new).and_return(meta)

               expect(TaskWorker).to receive(:new).with(hash_including(metadata: meta)).and_call_original

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: fake_persister([task_data]))
               end

               worker = QueueWorker.new(queue: config.queues.first, config: config)

               worker.work_one
            end

            it 'should pass the TaskWorker the task container' do
               task_data = {run_at: 1}
               container = double('container object')

               expect(TaskWorker).to receive(:new).with(hash_including(container: container)).and_call_original

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: fake_persister([task_data]))
                  c.provide_container container
               end

               worker = QueueWorker.new(queue: config.queues.first, config: config)

               worker.work_one
            end

            it 'should pass the TaskWorker the queue settings' do
               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: fake_persister([{run_at: 1}]))
               end
               queue  = config.queues.first

               expect(TaskWorker).to receive(:new).with(hash_including(queue: queue)).and_call_original

               worker = QueueWorker.new(queue: queue, config: config)

               worker.work_one
            end

            it 'should pass the TaskWorker the scheduler' do
               expect(TaskWorker).to receive(:new).with(hash_including(scheduler: an_instance_of(Scheduler))).and_call_original

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: fake_persister([{run_at: 1}]))
               end

               worker = QueueWorker.new(queue: config.queues.first, config: config)

               worker.work_one
            end

            it 'should run a TaskWorker for the first ready task' do
               task_data1 = {run_at: 1}
               task_data2 = {run_at: 1}
               task_data3 = {run_at: 1}

               expect(TaskWorker).to receive(:new).once.and_call_original

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: fake_persister([task_data1, task_data2, task_data3]))
               end

               worker = QueueWorker.new(queue: config.queues.first, config: config)

               worker.work_one
            end

            it 'should not start any TaskWorkers for unready tasks' do
               now = Time.now

               task_data1 = {run_at: now}
               task_data2 = {run_at: now + 1}

               expect(TaskWorker).to receive(:new).ordered.and_call_original
               expect(TaskWorker).to_not receive(:new).ordered.and_call_original

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: fake_persister([task_data1, task_data2]))
               end

               worker = QueueWorker.new(queue: config.queues.first, config: config)

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

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: persister)
               end

               worker = QueueWorker.new(queue: config.queues.first, config: config)

               expect(persister).to receive(:delete).with(task_data[:id])

               worker.work_one
            end
         end

         context 'TaskWorker fails for fails For The Last Time' do
            # Vader:
            # it 'should promote Captain Piett to Admiral Piett'

            it 'should update the task' do
               {queueA: 0, queueB: 1}.each do |name, max_attempts|
                  id        = double('id')
                  task_data = {
                        id:     id,
                        run_at: 0
                  }

                  persister = fake_persister([task_data])

                  config = Config.new do |c|
                     c.define_queue(name, Test::Task::Fail,
                                    store:         persister,
                                    update_period: 0,
                                    max_attempts:  max_attempts)
                  end

                  # allow_any_instance_of(TaskWorker).to receive(:to_h).and_return(task_hash)

                  worker = QueueWorker.new(queue: name, config: config)

                  expect(persister).to receive(:update).with(id, hash_including(run_at: nil,
                                                                                queue:  name))

                  worker.work_one
               end
            end
         end
      end
   end

   describe Loggable do
      let(:loggable) do
         Test::TestLoggable.new
      end

      let(:test_task) { Test::Task::AllHooks }

      describe '#open_log!' do
         include FakeFS::SpecHelpers

         before(:each) do
            FakeFS.clear! if FakeFS.activated?
         end

         let(:log_dir) { Pathname.new '/var/log' }

         context 'falsey log level' do
            let(:config) do
               Config.new do |c|
                  c.log_with level:     nil,
                             directory: log_dir
               end
            end

            it 'should NOT create the log directory' do
               loggable.open_log!('test-log', config)

               expect(Dir.glob('/var/log/*')).to be_empty
            end

            it 'should NOT create a logger instance' do
               expect(Logger).to_not receive(:new)

               loggable.open_log!('test-log', config)
            end

            it 'should NOT create a log file for this worker' do
               loggable.open_log!('test-log', config)

               expect(Dir.glob('*.log')).to be_empty
            end
         end

         context 'truthy log level' do
            let(:config) do
               Config.new do |c|
                  c.log_with level:     1,
                             directory: log_dir
               end
            end

            it 'should create the log directory if it does not exist' do
               loggable.open_log!('test-log', config)

               expect(log_dir).to be_directory
            end

            it 'should append to the log file if it already exists' do
               log_path = log_dir / 'existing.log'

               existing_data = 'this is text from before'
               new_data      = 'new text'

               log_dir.mkpath
               log_path.write(existing_data)

               logger = loggable.open_log!('existing', config)
               logger.info(new_data)

               expect(log_path.read).to start_with(existing_data)
               expect(log_path.read.strip).to end_with(new_data)
            end

            it 'should log at the provided level' do
               logger = Logger.new(StringIO.new)

               Logger::Severity.constants.each do |level|
                  config = Config.new do |c|
                     c.log_with level: level
                  end

                  expect(Logger).to receive(:new).with(anything, anything, anything, hash_including(level: level))
                                                 .and_return logger

                  loggable.open_log!('test-log', config)
               end
            end

            it 'should include the log name in the log output' do
               ['some-name', 'another name'].each do |name|
                  logger = loggable.open_log!(name, config)
                  logger.info('test')

                  log_contents = Pathname.new("#{ log_dir }/#{ name }.log").read

                  expect(log_contents).to include("-- #{ name }:")
               end
            end

            it 'should use the provided shift age and size' do
               logger = Logger.new(StringIO.new)

               size   = double('size')
               age    = double('age')
               config = Config.new do |c|
                  c.log_with shift_size: size, shift_age: age
               end

               expect(Logger).to receive(:new).with(anything, age, size, anything).and_return(logger)

               loggable.open_log!('test-config', config)
            end
         end
      end
   end
end
