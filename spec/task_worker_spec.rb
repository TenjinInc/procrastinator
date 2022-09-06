# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe TaskWorker do
      let(:queue) { Procrastinator::Queue.new(name: :test_queue, task_class: Test::Task::AllHooks) }
      let(:data_str) { JSON.dump('itsa me, a data-o') }
      let(:meta) { TaskMetaData.new(id: 1, queue: queue, data: data_str) }
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
            task   = double('task')
            worker = TaskWorker.new(task)

            expect(worker.task).to eq(task)
         end
      end

      describe '#work' do
         let(:task_handler) { Test::Task::AllHooks.new }
         let(:task) { Task.new(meta, task_handler) }
         let(:fail_handler) { Test::Task::Fail.new }
         let(:fail_task) { Task.new(meta, fail_handler) }

         context 'run hook' do
            it 'should call task #run' do
               expect(task).to receive(:run)

               worker = TaskWorker.new(task)

               worker.work
            end

            it 'should NOT call #run when the expiry time has passed' do
               expect(task).to_not receive(:run)

               meta = TaskMetaData.new(queue:     queue,
                                       expire_at: 0)

               worker = TaskWorker.new(Task.new(meta, task_handler))
               worker.work
            end
         end

         context 'success hook' do
            it 'should call task #success when #run completes without error' do
               expect(task_handler).to receive(:success)

               worker = TaskWorker.new(task)

               worker.work
            end

            it 'should NOT call task #success when #run errors' do
               expect(fail_task).to_not receive(:success)

               worker = TaskWorker.new(fail_task)

               worker.work
            end

            it 'should complain to stderr when #success errors' do
               err = 'testing success block error handling'

               allow(task_handler).to receive(:success).and_raise(err)

               worker = TaskWorker.new(task)

               expect { worker.work }.to output("Success hook error: #{ err }\n").to_stderr
            end

            it 'should do nothing if the task does not include #success' do
               klass = Class.new do
                  def run
                  end
               end

               task = Task.new(meta, klass.new)

               worker = TaskWorker.new(task)

               expect { worker.work }.to_not output.to_stderr
            end

            it 'should pass the result of #run to #success' do
               result = double('run result')

               allow(task).to receive(:run).and_return(result)
               expect(task_handler).to receive(:success).with(result)

               worker = TaskWorker.new(task)
               worker.work
            end

            it 'should log #success at debug level' do
               logger = double('logger')

               worker = TaskWorker.new(task,
                                       logger: logger)

               expect(logger).to receive(:debug).with("Task completed: #{ queue.name.to_sym }#1 [#{ data_str }]")

               worker.work
            end
         end

         context 'fail hook' do
            it 'should #fail when #run errors' do
               expect(fail_task).to receive(:fail)

               worker = TaskWorker.new(fail_task)
               worker.work
            end

            it 'should #fail when #run duration exceeds timeout and provide a timeout error' do
               timeout = 0.1 # can't be 0. timeout doesn't actually do timeout stuff if given 0
               allow(fail_task).to receive(:run) do
                  sleep(timeout + 0.1)
               end

               expect(fail_handler).to receive(:fail).with(Timeout::Error)

               worker = TaskWorker.new(fail_task)
               worker.work(timeout)
            end

            it 'should call #fail if nil max_attempts given and #run errors' do
               unlimited_queue = Procrastinator::Queue.new(name:         :unlimited_queue,
                                                           task_class:   Test::Task::Fail,
                                                           max_attempts: nil)

               expect(fail_handler).to receive(:fail)

               task   = Task.new(TaskMetaData.new(queue: unlimited_queue), fail_handler)
               worker = TaskWorker.new(task)
               worker.work
            end

            it 'should NOT #fail when #success errors' do
               task_handler = double('bad success')

               allow(task_handler).to receive(:run)
               allow(task_handler).to receive(:success).and_raise('task failed successfully')

               expect(task_handler).to_not receive(:fail)

               task = Task.new(meta, task_handler)

               worker = TaskWorker.new(task)

               # silence the stdout warning
               expect do
                  worker.work
               end.to output.to_stderr
            end

            it 'should NOT call #fail if calling #final_fail' do
               final_queue = Queue.new(name:         :final_queue,
                                       task_class:   Test::Task::Fail,
                                       max_attempts: 0)

               allow(fail_handler).to receive(:final_fail)
               expect(fail_handler).to_not receive(:fail)

               task = Task.new(TaskMetaData.new(queue: final_queue), fail_handler)

               worker = TaskWorker.new(task)
               worker.work
            end

            it 'should handle errors from task #fail' do
               task_handler = double('exploding fail task')

               err = 'fail error'

               allow(task_handler).to receive(:run).and_raise('run error')
               allow(task_handler).to receive(:fail).and_raise(err)

               task   = Task.new(meta, task_handler)
               worker = TaskWorker.new(task)

               expect { worker.work }.to output("Fail hook error: #{ err }\n").to_stderr
            end

            it 'should do nothing if the task does not include #fail' do
               klass = Class.new do
                  def run
                  end
               end

               task   = Task.new(meta, klass.new)
               worker = TaskWorker.new(task)

               expect { worker.work }.to_not output.to_stderr
            end

            it 'should record the most recent failure time' do
               start_time = Time.now

               Timecop.freeze(start_time) do
                  delay = 100

                  allow(fail_handler).to receive(:run) do
                     Timecop.travel(delay)
                     raise 'fake error'
                  end

                  worker = TaskWorker.new(fail_task)

                  worker.work

                  expect(meta.last_fail_at.to_i).to eq start_time.to_i + delay
               end
            end

            it 'should reschedule for the future' do
               meta   = TaskMetaData.new(run_at:         0,
                                         initial_run_at: 0,
                                         queue:          fail_queue)
               task   = Task.new(meta, fail_handler)
               worker = TaskWorker.new(task)
               worker.work

               expect(meta.run_at).to be > meta.initial_run_at
            end

            it 'should reschedule on an increasing basis' do
               queue = Procrastinator::Queue.new(name:         :reschedule_queue,
                                                 task_class:   Test::Task::Fail,
                                                 max_attempts: 4)

               meta   = TaskMetaData.new(run_at: 0, queue: queue)
               task   = Task.new(meta, fail_handler)
               worker = TaskWorker.new(task)

               (1..3).each do |i|
                  previous_time = meta.run_at

                  worker.work

                  expected_time = previous_time + (30 + (i ** 4))

                  actual_time = meta.run_at

                  expect(actual_time).to eq expected_time
               end
            end

            it 'should NOT reschedule when run_at is nil' do
               meta   = TaskMetaData.new(run_at: nil, queue: fail_queue)
               task   = Task.new(meta, fail_handler)
               worker = TaskWorker.new(task)
               worker.work

               expect(meta.run_at).to be_nil
            end

            it 'should record the error and trace in last_error' do
               worker = TaskWorker.new(fail_task)
               worker.work

               expect(meta.last_error).to start_with 'Task failed: '
               expect(meta.last_error).to include 'asplode' # message from the FailTask
               expect(meta.last_error).to match(/(.*\n)+/) # poor version of checking for backtrace, but it works for now
            end

            it 'should pass in the error to #fail' do
               err = StandardError.new('fake error')
               allow(fail_handler).to receive(:run).and_raise(err)

               expect(fail_handler).to receive(:fail).with(err)

               worker = TaskWorker.new(fail_task)
               worker.work
            end

            it 'should log #fail at debug level' do
               logger = Logger.new(StringIO.new)

               worker = TaskWorker.new(fail_task, logger: logger)

               expect(logger).to receive(:debug).with("Task failed: #{ queue.name }#1 [#{ data_str }]")

               worker.work
            end
         end

         context 'final_fail hook' do
            let(:meta) { TaskMetaData.new(id: 1, queue: final_fail_queue, data: data_str) }

            it 'should call #final_fail if #run errors more than given max_attempts' do
               max_attempts = 3

               overfail_queue = Queue.new(name:         :overfail_queue,
                                          task_class:   Test::Task::Fail,
                                          max_attempts: max_attempts)

               task   = Task.new(TaskMetaData.new(queue: overfail_queue), fail_task)
               worker = TaskWorker.new(task)

               expect(fail_task).to receive(:final_fail)

               max_attempts.times do
                  worker.work
               end
            end

            it 'should call #final_fail when the expiry time has passed' do
               %w[2022-04-01T12:15:00-06:00 2021-02-07T16:25:00-06:00].each do |time|
                  expect(fail_handler).to receive(:final_fail).with(instance_of(Task::ExpiredError))

                  meta = TaskMetaData.new(queue: queue, expire_at: time)

                  task   = Task.new(meta, fail_handler)
                  worker = TaskWorker.new(task)
                  worker.work
               end
            end

            it 'should NOT error or call #final_fail if nil max_attempts given' do
               unlimited_queue = Procrastinator::Queue.new(name:         :unlimited_queue,
                                                           task_class:   Test::Task::Fail,
                                                           max_attempts: nil)

               meta   = TaskMetaData.new(queue: unlimited_queue)
               task   = Task.new(meta, fail_handler)
               worker = TaskWorker.new(task)

               expect(fail_task).to_not receive(:final_fail)

               worker.work
            end

            it 'should handle errors from #final_fail' do
               err = 'final fail error'

               allow(fail_handler).to receive(:final_fail).and_raise(err)

               worker = TaskWorker.new(fail_task)

               expect do
                  worker.work
               end.to output("Final_fail hook error: #{ err }\n").to_stderr
            end

            it 'should do nothing if the task does not include #final_fail' do
               worker = TaskWorker.new(fail_task)

               expect do
                  worker.work
               end.to_not output.to_stderr
            end

            it 'should record the final failure time' do
               start_time = Time.now
               delay      = 100

               Timecop.freeze(start_time) do
                  allow(fail_handler).to receive(:run) do
                     Timecop.travel(delay)
                     raise 'fake error'
                  end

                  worker = TaskWorker.new(fail_task)
                  worker.work

                  expect(meta.last_fail_at.to_i).to eq start_time.to_i + delay
               end
            end

            it 'should mark the task as permanently failed' do
               worker = TaskWorker.new(fail_task)
               worker.work

               expect(meta.run_at).to be nil
            end

            it 'should record that the expiry time has passed with trace' do
               meta   = TaskMetaData.new(expire_at: 0, queue: queue)
               task   = Task.new(meta, fail_handler)
               worker = TaskWorker.new(task)
               worker.work

               expect(meta.last_error).to start_with 'Task expired: '
               expect(meta.last_error).to match(/(.*\n)+/) # poor version of checking for backtrace, but it works for now
            end

            it 'should record the error and trace in last_error' do
               worker = TaskWorker.new(fail_task)
               worker.work

               expect(meta.last_error).to start_with 'Task failed too many times: '
               expect(meta.last_error).to match(/(.*\n)+/) # poor version of checking for backtrace, but it works for now
            end

            it 'should pass in the error to #final_fail' do
               err = StandardError.new('fake error')
               allow(fail_handler).to receive(:run).and_raise(err)

               expect(fail_handler).to receive(:final_fail).with(err)

               worker = TaskWorker.new(fail_task)
               worker.work
            end

            it 'should log #final_fail at debug level' do
               err    = StandardError.new('fake error')
               logger = Logger.new(StringIO.new)

               allow(fail_handler).to receive(:run).and_raise(err)

               worker = TaskWorker.new(fail_task, logger: logger)

               err = "Task failed permanently: #{ final_fail_queue.name }#1 [#{ data_str }]"
               expect(logger).to receive(:debug).with(err)

               worker.work
            end
         end
      end
   end
end
