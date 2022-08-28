# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe TaskWorker do
      let(:queue) { Procrastinator::Queue.new(name: :test_queue, task_class: Test::Task::AllHooks) }
      let(:meta) { TaskMetaData.new(queue: queue) }
      let(:fail_queue) { Procrastinator::Queue.new(name: :fail_queue, task_class: Test::Task::Fail) }
      let(:final_fail_queue) { Procrastinator::Queue.new(name: :fail_queue, task_class: Test::Task::Fail, max_attempts: 0) }

      describe '#inititalize' do
         let(:task_class) do
            Class.new do
               def run
               end
            end
         end
         let(:queue) { Procrastinator::Queue.new(name: :test_queue, task_class: task_class, store: fake_persister) }

         it 'should remember the given task' do
            task = double('task')
            meta = double('meta')
            worker = TaskWorker.new(metadata: meta, task: task)

            expect(worker.task).to eq(task)
         end
      end

      describe '#work' do
         let(:task) { Test::Task::AllHooks.new }
         let(:fail_task) { Test::Task::Fail.new }

         context 'run hook' do
            it 'should call task #run' do
               expect(task).to receive(:run)

               worker = TaskWorker.new(metadata: meta, task: task)

               worker.work
            end

            it 'should increase number of attempts when #run is called' do
               worker = TaskWorker.new(metadata: meta, task: task)

               (1..3).each do |i|
                  worker.work
                  expect(worker.attempts).to eq i
               end
            end

            it 'should NOT call #run when the expiry time has passed' do
               expect(task).to_not receive(:run)

               worker = TaskWorker.new(metadata: TaskMetaData.new(queue:     queue,
                                                                  expire_at: 0),
                                       task:     task)
               worker.work
            end
         end

         context 'success hook' do
            it 'should call task #success when #run completes without error' do
               expect(task).to receive(:success)

               worker = TaskWorker.new(metadata: meta, task: task)

               worker.work
            end

            it 'should NOT call task #success when #run errors' do
               expect(fail_task).to_not receive(:success)

               worker = TaskWorker.new(metadata: meta, task: fail_task)

               worker.work
            end

            it 'should complain to stderr when #success errors' do
               err = 'testing success block error handling'

               allow(task).to receive(:success).and_raise(err)

               worker = TaskWorker.new(metadata: meta, task: task)

               expect { worker.work }.to output("Success hook error: #{ err }\n").to_stderr
            end

            it 'should do nothing if the task does not include #success' do
               klass = Class.new do
                  def run
                  end
               end

               worker = TaskWorker.new(metadata: meta, task: klass.new)

               expect { worker.work }.to_not output.to_stderr
            end

            it 'should blank the error message' do
               worker = TaskWorker.new(metadata: TaskMetaData.new(last_error: 'asplode',
                                                                  queue:      queue),
                                       task:     double('task', run: nil))

               worker.work

               expect(worker.last_error).to be nil
            end

            it 'should blank the error time' do
               worker = TaskWorker.new(metadata: TaskMetaData.new(last_fail_at: double('failtime'),
                                                                  queue:        queue),
                                       task:     double('task', run: nil))

               worker.work

               expect(worker.last_fail_at).to be nil
            end

            it 'should pass the result of #run to #success' do
               result = double('run result')

               allow(task).to receive(:run).and_return(result)
               expect(task).to receive(:success).with(result)

               worker = TaskWorker.new(metadata: meta, task: task)
               worker.work
            end

            it 'should log #success at debug level' do
               logger   = double('logger')
               data_str = JSON.dump('some data text')

               worker = TaskWorker.new(task:     task,
                                       logger:   logger,
                                       metadata: TaskMetaData.new(last_fail_at: double('failtime'),
                                                                  data:         data_str,
                                                                  queue:        queue))

               expect(logger).to receive(:debug).with("Task completed: #{ queue.name.to_sym } [#{ data_str }]")

               worker.work
            end
         end

         context 'fail hook' do
            it 'should #fail when #run errors' do
               expect(fail_task).to receive(:fail)

               worker = TaskWorker.new(metadata: meta, task: fail_task)
               worker.work
            end

            it 'should #fail when #run duration exceeds timeout and provide a timeout error' do
               timeout = 0.1 # can't be 0. timeout doesn't actually do timeout stuff if given 0
               allow(fail_task).to receive(:run) do
                  sleep(timeout + 0.1)
               end

               expect(fail_task).to receive(:fail).with(Timeout::Error)

               worker = TaskWorker.new(metadata: meta,
                                       task:     fail_task)
               worker.work(timeout)
            end

            it 'should call #fail if nil max_attempts given and #run errors' do
               unlimited_queue = Procrastinator::Queue.new(name:         :unlimited_queue,
                                                           task_class:   Test::Task::Fail,
                                                           max_attempts: nil)

               expect(fail_task).to receive(:fail)

               worker = TaskWorker.new(metadata: TaskMetaData.new(queue: unlimited_queue),
                                       task:     fail_task)
               worker.work
            end

            it 'should NOT #fail when #success errors' do
               task = double('bad success')

               allow(task).to receive(:run)
               allow(task).to receive(:success).and_raise('task failed successfully')

               expect(task).to_not receive(:fail)

               worker = TaskWorker.new(metadata: meta, task: task)

               # silence the stdout warning
               expect do
                  worker.work
               end.to output.to_stderr
            end

            it 'should NOT call #fail if calling #final_fail' do
               final_queue = Queue.new(name:         :final_queue,
                                       task_class:   Test::Task::Fail,
                                       max_attempts: 0)

               allow(fail_task).to receive(:final_fail)
               expect(fail_task).to_not receive(:fail)

               worker = TaskWorker.new(metadata: TaskMetaData.new(queue: final_queue), task: fail_task)
               worker.work
            end

            it 'should handle errors from task #fail' do
               task = double('exploding fail task')

               err = 'fail error'

               allow(task).to receive(:run).and_raise('run error')
               allow(task).to receive(:fail).and_raise(err)

               worker = TaskWorker.new(metadata: meta, task: task)

               expect { worker.work }.to output("Fail hook error: #{ err }\n").to_stderr
            end

            it 'should do nothing if the task does not include #fail' do
               klass  = Class.new do
                  def run
                  end
               end
               worker = TaskWorker.new(metadata: meta, task: klass.new)

               expect { worker.work }.to_not output.to_stderr
            end

            it 'should record the most recent failure time' do
               start_time = Time.now

               Timecop.freeze(start_time) do
                  delay = 100

                  allow(fail_task).to receive(:run) do
                     Timecop.travel(delay)
                     raise 'fake error'
                  end

                  worker = TaskWorker.new(metadata: meta, task: fail_task)

                  worker.work

                  expect(worker.last_fail_at).to eq start_time.to_i + delay
               end
            end

            it 'should reschedule for the future' do
               worker = TaskWorker.new(metadata: TaskMetaData.new(run_at:         0,
                                                                  initial_run_at: 0,
                                                                  queue:          fail_queue),
                                       task:     fail_task)
               worker.work

               expect(worker.run_at).to be > worker.initial_run_at
            end

            it 'should reschedule on an increasing basis' do
               queue = Procrastinator::Queue.new(name:         :reschedule_queue,
                                                 task_class:   Test::Task::Fail,
                                                 max_attempts: 4)

               worker = TaskWorker.new(metadata: TaskMetaData.new(run_at: 0,
                                                                  queue:  queue),
                                       task:     fail_task)

               (1..3).each do |i|
                  previous_time = worker.run_at

                  worker.work

                  expected_time = previous_time + (30 + (i ** 4))

                  actual_time = worker.run_at

                  expect(actual_time).to eq expected_time
               end
            end

            it 'should NOT reschedule when run_at is nil' do
               worker = TaskWorker.new(metadata: TaskMetaData.new(run_at: nil,
                                                                  queue:  fail_queue),
                                       task:     fail_task)
               worker.work

               expect(worker.run_at).to be_nil
            end

            it 'should record the error and trace in last_error' do
               worker = TaskWorker.new(metadata: meta, task: fail_task)
               worker.work

               expect(worker.last_error).to start_with 'Task failed: '
               expect(worker.last_error).to include 'asplode' # message from the FailTask
               expect(worker.last_error).to match(/(.*\n)+/) # poor version of checking for backtrace, but it works for now
            end

            it 'should pass in the error to #fail' do
               err = StandardError.new('fake error')
               allow(fail_task).to receive(:run).and_raise(err)

               expect(fail_task).to receive(:fail).with(err)

               worker = TaskWorker.new(metadata: meta, task: fail_task)
               worker.work
            end

            it 'should log #fail at debug level' do
               data       = 'itsa me, a data-o'
               task_class = Class.new do
                  def run
                     raise 'asplode'
                  end
               end

               logger = Logger.new(StringIO.new)

               queue = Procrastinator::Queue.new(name: :test, task_class: task_class)

               worker = TaskWorker.new(metadata: TaskMetaData.new(data:  JSON.dump(data),
                                                                  queue: queue),
                                       logger:   logger,
                                       task:     fail_task)

               expect(logger).to receive(:debug).with("Task failed: #{ queue.name } with #{ JSON.dump(data) }")

               worker.work
            end
         end

         context 'final_fail hook' do
            let(:meta) { TaskMetaData.new(queue: final_fail_queue) }

            it 'should call #final_fail if #run errors more than given max_attempts' do
               max_attempts = 3

               overfail_queue = Queue.new(name:         :overfail_queue,
                                          task_class:   Test::Task::Fail,
                                          max_attempts: max_attempts)

               worker = TaskWorker.new(metadata: TaskMetaData.new(queue: overfail_queue),
                                       task:     fail_task)

               expect(fail_task).to receive(:final_fail)

               max_attempts.times do
                  worker.work
               end
            end

            it 'should call #final_fail when the expiry time has passed' do
               (0..3).each do |i|
                  expect(fail_task).to receive(:final_fail).with(satisfy do |arg|
                     arg.is_a?(TaskExpiredError) && arg.message == "task is over its expiry time of #{ i }"
                  end)

                  worker = TaskWorker.new(task:     fail_task,
                                          metadata: TaskMetaData.new(expire_at: i,
                                                                     queue:     queue))
                  worker.work
               end
            end

            it 'should NOT error or call #final_fail if nil max_attempts given' do
               unlimited_queue = Procrastinator::Queue.new(name:         :unlimited_queue,
                                                           task_class:   Test::Task::Fail,
                                                           max_attempts: nil)

               worker = TaskWorker.new(metadata: TaskMetaData.new(queue: unlimited_queue),
                                       task:     fail_task)

               expect(fail_task).to_not receive(:final_fail)

               worker.work
            end

            it 'should handle errors from #final_fail' do
               err = 'final fail error'

               allow(fail_task).to receive(:final_fail).and_raise(err)

               worker = TaskWorker.new(metadata: meta, task: fail_task)

               expect do
                  worker.work
               end.to output("Final_fail hook error: #{ err }\n").to_stderr
            end

            it 'should do nothing if the task does not include #final_fail' do
               worker = TaskWorker.new(metadata: meta, task: fail_task)

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

                  worker = TaskWorker.new(metadata: meta, task: fail_task)
                  worker.work

                  expect(worker.last_fail_at).to eq start_time.to_i + delay
               end
            end

            it 'should mark the task as permanently failed' do
               worker = TaskWorker.new(metadata: meta, task: fail_task)
               worker.work

               expect(worker.run_at).to be nil
            end

            it 'should record that the expiry time has passed with trace' do
               worker = TaskWorker.new(task: fail_task, metadata: TaskMetaData.new(expire_at: 0, queue: queue))
               worker.work

               expect(worker.last_error).to start_with 'Task expired: '
               expect(worker.last_error).to match(/(.*\n)+/) # poor version of checking for backtrace, but it works for now
            end

            it 'should record the error and trace in last_error' do
               worker = TaskWorker.new(metadata: meta, task: fail_task)
               worker.work

               expect(worker.last_error).to start_with 'Task failed too many times: '
               expect(worker.last_error).to match(/(.*\n)+/) # poor version of checking for backtrace, but it works for now
            end

            it 'should pass in the error to #final_fail' do
               err = StandardError.new('fake error')
               allow(fail_task).to receive(:run).and_raise(err)

               expect(fail_task).to receive(:final_fail).with(err)

               worker = TaskWorker.new(metadata: meta, task: fail_task)
               worker.work
            end

            it 'should log #final_fail at debug level' do
               err    = StandardError.new('fake error')
               logger = Logger.new(StringIO.new)

               allow(fail_task).to receive(:run).and_raise(err)

               worker = TaskWorker.new(metadata: meta,
                                       logger:   logger,
                                       task:     fail_task)

               expect(logger).to receive(:debug).with("Task failed permanently: #{ JSON.dump(fail_task) }")

               worker.work
            end
         end
      end
   end
end
