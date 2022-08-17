# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe TaskWorker do
      let(:queue) { Procrastinator::Queue.new(name: :test_queue, task_class: Test::Task::AllHooks) }
      let(:meta) { TaskMetaData.new }
      let(:fail_queue) { Procrastinator::Queue.new(name: :fail_queue, task_class: Test::Task::Fail) }
      let(:final_fail_queue) { Procrastinator::Queue.new(name: :fail_queue, task_class: Test::Task::Fail, max_attempts: 0) }

      describe '#inititalize' do
         let(:task_instance) { double('task', run: nil) }
         let(:task_class) { double('task class', new: task_instance) }
         let(:queue) { Procrastinator::Queue.new(name: :test_queue, task_class: task_class) }

         it 'should complain when no queue is given' do
            expect do
               TaskWorker.new(metadata: meta)
            end.to raise_error(ArgumentError, 'missing keyword: queue')
         end

         it 'should complain if task does not support #run' do
            task       = double('task instance')
            task_class = double('BadTaskClass', new: task)

            queue = Procrastinator::Queue.new(name: :test_queue, task_class: task_class)

            expect do
               TaskWorker.new(metadata: meta, queue: queue)
            end.to raise_error(MalformedTaskError, "task #{ task.class } does not support #run method")
         end

         it 'should build a new task instance using the queue settings' do
            meta = TaskMetaData.new

            expect(task_class).to receive(:new).with(no_args)

            TaskWorker.new(metadata: meta, queue: queue)
         end

         context 'data injection' do
            let(:task_class) do
               Class.new do
                  include Procrastinator::Task

                  def run
                  end
               end
            end

            let(:task) { task_class.new }
            let(:meta) { TaskMetaData.new }

            before(:each) do
               allow(task_class).to receive(:new).and_return(task)
            end

            it 'should provide the data to the new task instance if requested' do
               task_class.task_attr :data

               meta = TaskMetaData.new(data: JSON.dump('data here'))

               queue = Procrastinator::Queue.new(name:       :test_queue,
                                                 task_class: task_class)

               expect(task).to receive(:data=).with(meta.data)

               TaskWorker.new(metadata: meta, queue: queue)
            end

            it 'should provide the container to the new task instance if requested' do
               task_class.task_attr :container

               container = double('container')

               queue = Procrastinator::Queue.new(name:       :test_queue,
                                                 task_class: task_class)

               expect(task).to receive(:container=).with(container)

               TaskWorker.new(metadata: meta, queue: queue, container: container)
            end

            it 'should provide the logger to the new task instance if requested' do
               task_class.task_attr :logger

               logger = Logger.new(StringIO.new)

               expect(Logger).to receive(:new).and_return(logger)

               queue = Procrastinator::Queue.new(name:       :test_queue,
                                                 task_class: task_class)

               expect(task).to receive(:logger=).with(logger)

               TaskWorker.new(metadata: meta, queue: queue)
            end

            it 'should provide the scheduler to the new task instance if requested' do
               task_class.task_attr :scheduler

               scheduler = double('scheduler')

               expect(task).to receive(:scheduler=).with(scheduler)

               TaskWorker.new(metadata:  meta,
                              queue:     queue,
                              scheduler: scheduler)
            end
         end
      end

      describe '#work' do
         context 'run hook' do
            it 'should call task #run' do
               task = double('task')

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               expect(task).to receive(:run)
               allow(task).to receive(:success)

               worker = TaskWorker.new(metadata: meta, queue: queue)

               worker.work
            end

            it 'should increase number of attempts when #run is called' do
               task = double('task')

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               allow(task).to receive(:run)
               allow(task).to receive(:success)

               worker = TaskWorker.new(metadata: meta, queue: queue)

               (1..3).each do |i|
                  worker.work
                  expect(worker.attempts).to eq i
               end
            end

            it 'should NOT call #run when the expiry time has passed' do
               task = double('task')

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               expect(task).to_not receive(:run)

               worker = TaskWorker.new(metadata: TaskMetaData.new(expire_at: 0), queue: queue)
               worker.work
            end
         end

         context 'success hook' do
            it 'should call task #success when #run completes without error' do
               task = double('task')

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               allow(task).to receive(:run)
               expect(task).to receive(:success)

               worker = TaskWorker.new(metadata: meta, queue: queue)

               worker.work
            end

            it 'should NOT call task #success when #run errors' do
               task = Test::Task::Fail.new

               expect(task).to_not receive(:success)
               allow(task).to receive(:fail)

               allow(Test::Task::Fail).to receive(:new).and_return(task)

               worker = TaskWorker.new(metadata: meta, queue: queue)

               worker.work
            end

            it 'should complain to stderr when #success errors' do
               task = Test::Task::AllHooks.new
               err  = 'testing success block error handling'

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               allow(task).to receive(:success).and_raise(err)

               worker = TaskWorker.new(metadata: meta, queue: queue)

               expect { worker.work }.to output("Success hook error: #{ err }\n").to_stderr
            end

            it 'should do nothing if the task does not include #success' do
               queue = Procrastinator::Queue.new(name: :run_only, task_class: Test::Task::RunOnly)

               worker = TaskWorker.new(metadata: meta, queue: queue)

               expect { worker.work }.to_not output.to_stderr
            end

            it 'should blank the error message' do
               worker = TaskWorker.new(metadata: TaskMetaData.new(last_error: 'derp'), queue: queue)

               worker.work

               expect(worker.last_error).to be nil
            end

            it 'should blank the error time' do
               worker = TaskWorker.new(metadata: TaskMetaData.new(last_fail_at: double('failtime')), queue: queue)

               worker.work

               expect(worker.last_fail_at).to be nil
            end

            it 'should pass the result of #run to #success' do
               task   = double('task')
               result = double('run result')

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               allow(task).to receive(:run).and_return(result)
               expect(task).to receive(:success).with(result)

               worker = TaskWorker.new(metadata: meta, queue: queue)
               worker.work
            end

            it 'should log #success at debug level' do
               logger   = double('logger')
               data_str = JSON.dump('some data text')

               worker = TaskWorker.new(queue:    queue,
                                       logger:   logger,
                                       metadata: TaskMetaData.new(last_fail_at: double('failtime'),
                                                                  data:         data_str))

               expect(logger).to receive(:debug).with("Task completed: #{ Test::Task::AllHooks } [#{ data_str }]")

               worker.work
            end
         end

         context 'fail hook' do
            it 'should #fail when #run errors' do
               task = Test::Task::Fail.new

               allow(Test::Task::Fail).to receive(:new).and_return(task)

               expect(task).to receive(:fail)

               worker = TaskWorker.new(metadata: meta, queue: fail_queue)
               worker.work
            end

            it 'should #fail when #run duration exceeds timeout and provide a timeout error' do
               task    = Test::Task::Fail.new
               timeout = 0.1 # can't be 0. timeout doesn't actually do timeout stuff if given 0
               allow(task).to receive(:run) do
                  sleep(timeout + 0.1)
               end
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               timeout_queue = Procrastinator::Queue.new(name:       :timeout_queue,
                                                         task_class: Test::Task::Fail,
                                                         timeout:    timeout)

               expect(task).to receive(:fail).with(Timeout::Error)

               worker = TaskWorker.new(metadata: meta, queue: timeout_queue)
               worker.work
            end

            it 'should call #fail if nil max_attempts given and #run errors' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               allow(task).to receive(:run).and_raise('fake error')

               unlimited_queue = Procrastinator::Queue.new(name:         :unlimited_queue,
                                                           task_class:   Test::Task::Fail,
                                                           max_attempts: nil)

               expect(task).to receive(:fail)

               worker = TaskWorker.new(metadata: meta, queue: unlimited_queue)
               worker.work
            end

            it 'should NOT #fail when #success errors' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               allow(task).to receive(:run)
               allow(task).to receive(:success).and_raise('testing success block error handling')

               expect(task).to_not receive(:fail)

               worker = TaskWorker.new(metadata: meta, queue: fail_queue)

               # silence the stdout warning
               expect do
                  worker.work
               end.to output.to_stderr
            end

            it 'should NOT call #fail if calling #final_fail' do
               final_queue = Procrastinator::Queue.new(name:         :final_queue,
                                                       task_class:   Test::Task::Fail,
                                                       max_attempts: 0)

               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               allow(task).to receive(:run).and_raise('fake error')
               allow(task).to receive(:final_fail)
               expect(task).to_not receive(:fail)

               worker = TaskWorker.new(metadata: meta, queue: final_queue)
               worker.work
            end

            it 'should handle errors from task #fail' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               err = 'fail error'

               allow(task).to receive(:run).and_raise('run error')
               allow(task).to receive(:fail).and_raise(err)

               worker = TaskWorker.new(metadata: meta, queue: fail_queue)

               expect { worker.work }.to output("Fail hook error: #{ err }\n").to_stderr
            end

            it 'should do nothing if the task does not include #fail' do
               worker = TaskWorker.new(metadata: meta, queue: fail_queue)

               expect { worker.work }.to_not output.to_stderr
            end

            it 'should record the most recent failure time' do
               start_time = Time.now

               Timecop.freeze(start_time) do
                  delay = 100

                  fail_task = Test::Task::Fail.new
                  allow(Test::Task::Fail).to receive(:new).and_return(fail_task)

                  allow(fail_task).to receive(:run) do
                     Timecop.travel(delay)
                     raise 'fake error'
                  end

                  worker = TaskWorker.new(metadata: meta, queue: fail_queue)

                  worker.work

                  expect(worker.last_fail_at).to eq start_time.to_i + delay
               end
            end

            it 'should reschedule for the future' do
               worker = TaskWorker.new(metadata: TaskMetaData.new(run_at:         0,
                                                                  initial_run_at: 0),
                                       queue:    fail_queue)
               worker.work

               expect(worker.run_at).to be > worker.initial_run_at
            end

            it 'should reschedule on an increasing basis' do
               queue = Procrastinator::Queue.new(name:         :reschedule_queue,
                                                 task_class:   Test::Task::Fail,
                                                 max_attempts: 4)

               worker = TaskWorker.new(metadata: TaskMetaData.new(run_at: 0),
                                       queue:    queue)

               (1..3).each do |i|
                  previous_time = worker.run_at

                  worker.work

                  expected_time = previous_time + (30 + (i ** 4))

                  actual_time = worker.run_at

                  expect(actual_time).to eq expected_time
               end
            end

            it 'should NOT reschedule when run_at is nil' do
               worker = TaskWorker.new(metadata: TaskMetaData.new(run_at: nil),
                                       queue:    fail_queue)
               worker.work

               expect(worker.run_at).to be_nil
            end

            it 'should record the error and trace in last_error' do
               worker = TaskWorker.new(metadata: meta, queue: fail_queue)
               worker.work

               expect(worker.last_error).to start_with 'Task failed: '
               expect(worker.last_error).to include 'derp' # message from the FailTask
               expect(worker.last_error).to match(/(.*\n)+/) # poor version of checking for backtrace, but it works for now
            end

            it 'should pass in the error to #fail' do
               fail_task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(fail_task)

               err = StandardError.new('fake error')
               allow(fail_task).to receive(:run).and_raise(err)

               expect(fail_task).to receive(:fail).with(err)

               worker = TaskWorker.new(metadata: meta, queue: fail_queue)
               worker.work
            end

            it 'should log #fail at debug level' do
               data       = 'itsa me, a data-o'
               task       = double('task')
               task_class = double('task class', new: task)

               allow(task).to receive(:run).and_raise('derp')

               logger = Logger.new(StringIO.new)

               queue = Procrastinator::Queue.new(name: :test, task_class: task_class)

               worker = TaskWorker.new(metadata: TaskMetaData.new(data: JSON.dump(data)),
                                       logger:   logger,
                                       queue:    queue)

               expect(logger).to receive(:debug).with("Task failed: #{ queue.name } with #{ JSON.dump(data) }")

               worker.work
            end
         end

         context 'final_fail hook' do
            it 'should call #final_fail if #run errors more than given max_attempts' do
               max_attempts = 3

               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               overfail_queue = Procrastinator::Queue.new(name:         :overfail_queue,
                                                          task_class:   Test::Task::Fail,
                                                          max_attempts: max_attempts)

               worker = TaskWorker.new(metadata: meta, queue: overfail_queue)

               expect(task).to receive(:final_fail)

               max_attempts.times do
                  worker.work
               end
            end

            it 'should call #final_fail when the expiry time has passed' do
               (0..3).each do |i|
                  task = Test::Task::Fail.new
                  allow(Test::Task::Fail).to receive(:new).and_return(task)

                  expect(task).to receive(:final_fail).with(satisfy do |arg|
                     arg.is_a?(TaskExpiredError) && arg.message == "task is over its expiry time of #{ i }"
                  end)

                  worker = TaskWorker.new(queue:    fail_queue,
                                          metadata: TaskMetaData.new(expire_at: i))
                  worker.work
               end
            end

            it 'should NOT error or call #final_fail if nil max_attempts given' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               unlimited_queue = Procrastinator::Queue.new(name:         :unlimited_queue,
                                                           task_class:   Test::Task::Fail,
                                                           max_attempts: nil)

               worker = TaskWorker.new(metadata: meta, queue: unlimited_queue)

               expect(task).to_not receive(:final_fail)

               worker.work
            end

            it 'should handle errors from #final_fail' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               err = 'final fail error'

               allow(task).to receive(:final_fail).and_raise(err)

               worker = TaskWorker.new(metadata: meta, queue: final_fail_queue)

               expect do
                  worker.work
               end.to output("Final_fail hook error: #{ err }\n").to_stderr
            end

            it 'should do nothing if the task does not include #final_fail' do
               worker = TaskWorker.new(metadata: meta, queue: final_fail_queue)

               expect do
                  worker.work
               end.to_not output.to_stderr
            end

            it 'should record the final failure time' do
               fail_task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(fail_task)

               start_time = Time.now
               delay      = 100

               Timecop.freeze(start_time) do
                  allow(fail_task).to receive(:run) do
                     Timecop.travel(delay)
                     raise 'fake error'
                  end

                  worker = TaskWorker.new(metadata: meta, queue: final_fail_queue)
                  worker.work

                  expect(worker.last_fail_at).to eq start_time.to_i + delay
               end
            end

            it 'should mark the task as permanently failed' do
               worker = TaskWorker.new(metadata: meta, queue: final_fail_queue)
               worker.work

               expect(worker.run_at).to be nil
            end

            it 'should record that the expiry time has passed with trace' do
               worker = TaskWorker.new(queue: queue, metadata: TaskMetaData.new(expire_at: 0))
               worker.work

               expect(worker.last_error).to start_with 'Task expired: '
               expect(worker.last_error).to match(/(.*\n)+/) # poor version of checking for backtrace, but it works for now
            end

            it 'should record the error and trace in last_error' do
               worker = TaskWorker.new(metadata: meta, queue: final_fail_queue)
               worker.work

               expect(worker.last_error).to start_with 'Task failed too many times: '
               expect(worker.last_error).to match(/(.*\n)+/) # poor version of checking for backtrace, but it works for now
            end

            it 'should pass in the error to #final_fail' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               err = StandardError.new('fake error')
               allow(task).to receive(:run).and_raise(err)

               expect(task).to receive(:final_fail).with(err)

               worker = TaskWorker.new(metadata: meta, queue: final_fail_queue)
               worker.work
            end

            it 'should log #final_fail at debug level' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               err    = StandardError.new('fake error')
               logger = Logger.new(StringIO.new)

               allow(task).to receive(:run).and_raise(err)

               worker = TaskWorker.new(metadata: meta,
                                       logger:   logger,
                                       queue:    final_fail_queue)

               expect(logger).to receive(:debug).with("Task failed permanently: #{ JSON.dump(task) }")

               worker.work
            end
         end
      end

      describe '#to_h' do
         it 'should return the task hash and queue name' do
            queue          = double(name: :some_queue, task_class: Test::Task::AllHooks)
            run_at         = double('run_at_i')
            initial_run_at = double('initial_run_at_i')
            expire_at      = double('expire_at_i')
            attempts       = double('attempts')
            last_fail_at   = double('last_fail_at')
            last_error     = double('last_error')
            data           = JSON.dump('one data, please')

            task = TaskMetaData.new(id:             double('id'),
                                    attempts:       attempts,
                                    last_fail_at:   last_fail_at,
                                    last_error:     last_error,
                                    data:           data,
                                    initial_run_at: double('initial_run_at', to_i: initial_run_at),
                                    run_at:         double('run_at', to_i: run_at),
                                    expire_at:      double('expire_at', to_i: expire_at))

            worker = TaskWorker.new(metadata: task, queue: queue)

            expect(worker.to_h).to include(attempts:       attempts,
                                           run_at:         run_at,
                                           last_fail_at:   last_fail_at,
                                           last_error:     last_error,
                                           initial_run_at: initial_run_at,
                                           expire_at:      expire_at,
                                           queue:          :some_queue,
                                           data:           data)
         end
      end
   end
end
