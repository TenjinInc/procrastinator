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

      describe '#work!' do
         let(:config) do
            Config.new do |c|
               c.define_queue(:fast_queue, test_task, update_period: 0.01)
            end
         end

         # this needs to be here and not in init because they get initialized in the parent boot process
         # and if it is daemonized, the file handles may disappear
         it 'should start a new log' do
            worker = QueueWorker.new(queue: :fast_queue, config: config)

            allow(worker).to receive(:loop) # stub infiniloop

            expect(worker).to receive(:open_log!).and_call_original

            worker.work!
         end

         it 'should wait for update_period' do
            [0.01, 0.02].each do |period|
               config = Config.new do |c|
                  c.define_queue(:fast_queue, test_task, update_period: period, store: persister)
               end

               worker = QueueWorker.new(queue: :fast_queue, config: config)

               expect(worker).to receive(:loop) do |&block|
                  block.call
               end

               expect(worker).to receive(:sleep).with(period)

               worker.work!
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

            worker.work!
         end

         it 'should pass the TaskWorker the logger' do
            logger = Logger.new(StringIO.new)

            allow(Logger).to receive(:new).and_return(logger)

            config = Config.new do |c|
               c.define_queue(:fast_queue, test_task, update_period: 0, store: fake_persister([{run_at: 1}]))
            end

            expect(TaskWorker).to receive(:new).with(anything, hash_including(logger: logger)).and_call_original
            worker = QueueWorker.new(queue: :fast_queue, config: config)
            allow(worker).to receive(:loop).and_yield

            worker.work!
         end

         it 'should log starting a queue worker' do
            [:test1, :test2].each do |queue_name|
               config = Config.new do |c|
                  c.define_queue(queue_name, test_task, update_period: 0, store: persister)
               end

               worker = QueueWorker.new(queue: queue_name, config: config)
               allow(worker).to receive(:loop).and_yield
               worker.work!

               log_contents = Pathname.new("log/#{ queue_name }-queue-worker.log").read

               expect(log_contents).to include("Started worker thread to consume queue: #{ queue_name }")
            end
         end

         it 'should log fatal errors if logging' do
            worker = QueueWorker.new(queue: :fast_queue, config: config)

            allow(worker).to receive(:sleep) # stub sleep
            # control looping, otherwise infiniloop by design
            allow(worker).to receive(:loop) do |&block|
               block.call
            end

            err = 'some fatal error'
            allow(worker).to receive(:work_one).and_raise(err)

            expect do
               worker.work!
            end.to raise_error(RuntimeError, err)

            log = File.read('log/fast_queue-queue-worker.log')

            expect(log).to include("\tFATAL\t") # default fatal error notation in Ruby logger
            expect(log).to include(err)
         end

         it 'should NOT log fatal errors if NOT logging' do
            config = Config.new do |c|
               c.define_queue :fast_queue, test_task, update_period: 0.1
               c.log_with level: false
            end
            worker = QueueWorker.new(queue: :fast_queue, config: config)

            # stub sleep and loop
            allow(worker).to receive(:sleep)
            allow(worker).to receive(:loop) do |&block|
               block.call
            end

            err = 'some fatal error'
            allow(worker).to receive(:work_one).and_raise(err)

            expect do
               worker.work!
            end.to raise_error(RuntimeError, err)

            expect(Pathname.new('log/fast_queue-queue-worker.log')).to_not exist
         end

         # Errors are reraised to prevent the case where a single thread crashes semi-silently but the others continue.
         # The whole set would need to be started anyway. These errors are for fatal things like a corrupted/missing
         # data store.
         it 'should reraise fatal errors' do
            config = Config.new do |c|
               c.define_queue :fast_queue, test_task, update_period: 0.1
            end

            worker = QueueWorker.new(queue: :fast_queue, config: config)

            # stub sleep and loop
            allow(worker).to receive(:sleep)
            allow(worker).to receive(:loop) do |&block|
               block.call
            end

            err = 'some fatal error'
            allow(worker).to receive(:work_one).and_raise(RuntimeError, err)

            expect do
               worker.work!
            end.to raise_error(RuntimeError, err)
         end
      end

      describe '#work_one' do
         let(:config) do
            Config.new do |c|
               c.with_store(persister) do
                  c.define_queue(:email, test_task, update_period: 0.01)
                  c.define_queue(:cleanup, test_task, update_period: 0.01)
               end
            end
         end

         context 'loading and running tasks' do
            it 'should reload tasks every cycle' do
               task1 = double('task1', :container= => nil, :logger= => nil, :scheduler= => nil)
               task2 = double('task2', :container= => nil, :logger= => nil, :scheduler= => nil)

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

            it 'should do nothing when no tasks are found' do
               task_data = {address: 'neutral@example.com'}
               container = double('container object')

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: fake_persister([{run_at: 1, data: JSON.dump(task_data)}]))
                  c.provide_container container
               end

               worker = QueueWorker.new(queue: :email, config: config)

               expect(worker).to receive(:next_task).and_return(nil)

               worker.work_one
            end

            it 'should run a TaskWorker with the task metadata' do
               task_data = {run_at: 1}
               config    = Config.new do |c|
                  c.define_queue(:email, test_task, store: fake_persister([task_data]))
               end

               queue  = config.queues.first
               worker = QueueWorker.new(queue: queue, config: config)

               task = Task.new(TaskMetaData.new(queue: queue, run_at: 1), test_task.new)
               allow(worker).to receive(:next_task).and_return(task)

               expect(TaskWorker).to receive(:new).with(task, anything).and_call_original

               worker.work_one
            end

            it 'should run a TaskWorker with the queue timeout' do
               task_data = {run_at: 1}
               config    = Config.new do |c|
                  c.define_queue(:email, test_task, store: fake_persister([task_data]))
               end

               queue  = config.queues.first
               worker = QueueWorker.new(queue: queue, config: config)

               task_worker = double('task worker', successful?: true, id: nil)
               allow(TaskWorker).to receive(:new).and_return(task_worker)

               expect(task_worker).to receive(:work).with(queue&.timeout)

               worker.work_one
            end

            it 'should request a configured task handler' do
               task_data = {address: 'neutral@example.com'}
               container = double('container object')

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: fake_persister([{run_at: 1, data: JSON.dump(task_data)}]))
                  c.provide_container container
               end

               worker = QueueWorker.new(queue: :email, config: config)

               expect(worker).to receive(:next_task).with(hash_including(container: container,
                                                                         scheduler: an_instance_of(Scheduler)))

               worker.work_one
            end

            it 'should pass the TaskWorker the configured task handler' do
               task_data = {address: 'neutral@example.com'}
               container = double('container object')
               handler   = Test::Task::AllHooks.new

               config = Config.new do |c|
                  c.define_queue(:email, test_task, store: fake_persister([{run_at: 1, data: JSON.dump(task_data)}]))
                  c.provide_container container
               end

               meta   = TaskMetaData.new(queue: config.queues.first)
               task   = Task.new(meta, handler)
               worker = QueueWorker.new(queue: :email, config: config)

               allow(worker).to receive(:next_task).and_return(task)
               expect(TaskWorker).to receive(:new).with(task, anything).and_call_original

               worker.work_one
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
            # context 'darth_vader' { it 'should promote Captain Piett to Admiral Piett' }

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

                  worker = QueueWorker.new(queue: name, config: config)

                  expect(persister).to receive(:update).with(id, hash_including(run_at: nil,
                                                                                queue:  name))

                  worker.work_one
               end
            end

            it 'should NOT delete the task' do
               task_data = {
                     id:     double('id'),
                     run_at: 0
               }

               allow(persister).to receive(:read).and_return([task_data])

               config = Config.new do |c|
                  c.define_queue(:email, Test::Task::Fail, store: persister)
               end

               worker = QueueWorker.new(queue: config.queues.first, config: config)

               expect(persister).to_not receive(:delete)

               worker.work_one
            end
         end
      end

      describe '#halt' do
         let(:str_log) { StringIO.new }
         let(:logger) { Logger.new(str_log) }

         let(:config) do
            Config.new do |c|
               c.with_store(persister) do
                  c.define_queue(:email, test_task, update_period: 0.01)
                  c.define_queue(:reminders, test_task, update_period: 0.01)
               end
            end
         end

         before(:each) do
            allow(Logger).to receive(:new).and_return(logger)
         end

         it 'should close its logger' do
            expect(logger).to receive(:close)

            worker = QueueWorker.new(queue: :email, config: config)
            allow(worker).to receive(:loop).and_yield
            worker.work!
            worker.halt
         end

         it 'should NOT close its logger if nil' do
            expect(logger).to_not receive(:close)

            worker = QueueWorker.new(queue: :reminders, config: config)
            worker.halt
         end

         it 'should log clean shutdown' do
            [:email, :reminders].each do |queue_name|
               expect(logger).to receive(:close)

               worker = QueueWorker.new(queue: queue_name, config: config)
               allow(worker).to receive(:loop).and_yield
               worker.work!
               worker.halt

               expect(str_log.string.strip).to end_with "Halted worker on queue: #{ queue_name }"
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

                  expect(Logger).to receive(:new)
                                          .with(anything, anything, anything, hash_including(level: level))
                                          .and_return logger

                  loggable.open_log!('test-log', config)
               end
            end

            it 'should include the log name in the log output' do
               ['some-name', 'another name'].each do |name|
                  logger = loggable.open_log!(name, config)
                  logger.info('test')

                  log_contents = Pathname.new("#{ log_dir }/#{ name }.log").read

                  expect(log_contents).to match(/#{ name } \(\d+\):/)
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
