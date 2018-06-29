require 'spec_helper'

module Procrastinator
   describe TaskWorker do
      let(:queue) {Procrastinator::Queue.new(name: :test_queue, task_class: Test::Task::AllHooks)}
      let(:task) {Task.new}
      let(:fail_queue) {Procrastinator::Queue.new(name: :fail_queue, task_class: Test::Task::Fail)}
      let(:final_fail_queue) {Procrastinator::Queue.new(name: :fail_queue, task_class: Test::Task::Fail, max_attempts: 0)}

      describe '#inititalize' do
         let(:handler_instance) {double('handler', run: nil)}
         let(:handler_class) {double('handler class', new: handler_instance)}

         it 'should complain when no queue is given' do
            expect do
               TaskWorker.new(task: task)
            end.to raise_error(ArgumentError, 'missing keyword: queue')
         end

         it 'should complain if task does not support #run' do
            handler       = double('handler instance')
            handler_class = double('BadTaskClass', new: handler)

            queue = Procrastinator::Queue.new(name: :test_queue, task_class: handler_class)

            expect do
               TaskWorker.new(task: task, queue: queue)
            end.to raise_error(MalformedTaskError, "task #{handler.class} does not support #run method")
         end

         it 'should get a new handler instance from the task' do
            task = Task.new

            queue = Procrastinator::Queue.new(name:       :test_queue,
                                              task_class: handler_class)

            expect(task).to receive(:init_handler).with(handler_class).and_call_original

            TaskWorker.new(task: task, queue: queue)
         end
      end

      describe '#work' do

         context 'run hook' do
            it 'should call task handler #run' do
               handler = double('handler')

               allow(Test::Task::AllHooks).to receive(:new).and_return(handler)

               expect(handler).to receive(:run)
               allow(handler).to receive(:success)

               worker = TaskWorker.new(task: task, queue: queue)

               worker.work
            end

            it 'should increase number of attempts when #run is called' do
               handler = double('handler')

               allow(Test::Task::AllHooks).to receive(:new).and_return(handler)

               allow(handler).to receive(:run)
               allow(handler).to receive(:success)

               worker = TaskWorker.new(task: task, queue: queue)

               (1..3).each do |i|
                  worker.work
                  expect(worker.attempts).to eq i
               end
            end

            it 'should NOT call #run when the expiry time has passed' do
               handler = double('handler')

               allow(Test::Task::AllHooks).to receive(:new).and_return(handler)

               expect(handler).to_not receive(:run)

               worker = TaskWorker.new(task: Task.new(expire_at: 0), queue: queue)
               worker.work
            end

            it 'should pass in the context to #success as the first arg' do
               handler = double('handler')
               context = double('task_context')

               allow(Test::Task::AllHooks).to receive(:new).and_return(handler)

               expect(handler).to receive(:run).with(context, anything)
               allow(handler).to receive(:success)

               worker = TaskWorker.new(task: task, queue: queue)
               worker.work(context: context)
            end

            it 'should pass in the queue logger to #success as the second arg' do
               handler = double('handler')
               logger  = Logger.new(StringIO.new)

               allow(Test::Task::AllHooks).to receive(:new).and_return(handler)

               expect(handler).to receive(:run).with(anything, logger)
               allow(handler).to receive(:success)

               worker = TaskWorker.new(task: task, queue: queue)
               worker.work(logger: logger)
            end
         end

         context 'success hook' do
            it 'should call task handler #success when #run completes without error' do
               handler = double('handler')

               allow(Test::Task::AllHooks).to receive(:new).and_return(handler)

               allow(handler).to receive(:run)
               expect(handler).to receive(:success)

               worker = TaskWorker.new(task: task, queue: queue)

               worker.work
            end

            it 'should NOT call task handler #success when #run errors' do
               handler = Test::Task::Fail.new

               expect(handler).to_not receive(:success)
               allow(handler).to receive(:fail)

               allow(Test::Task::Fail).to receive(:new).and_return(handler)

               worker = TaskWorker.new(task: task, queue: queue)

               worker.work
            end

            it 'should complain to stderr when #success errors' do
               handler = Test::Task::AllHooks.new
               err     = 'testing success block error handling'

               allow(Test::Task::AllHooks).to receive(:new).and_return(handler)

               allow(handler).to receive(:success).and_raise(err)

               worker = TaskWorker.new(task: task, queue: queue)

               expect {worker.work}.to output("Success hook error: #{err}\n").to_stderr
            end

            it 'should do nothing if the task handler does not include #success' do
               queue = Procrastinator::Queue.new(name: :run_only, task_class: Test::Task::RunOnly)

               worker = TaskWorker.new(task: task, queue: queue)

               expect {worker.work}.to_not output.to_stderr
            end

            it 'should blank the error message' do
               worker = TaskWorker.new(task: Task.new(last_error: 'derp'), queue: queue,)

               worker.work

               expect(worker.last_error).to be nil
            end

            it 'should blank the error time' do
               worker = TaskWorker.new(task: Task.new(last_fail_at: double('failtime')), queue: queue)

               worker.work

               expect(worker.last_fail_at).to be nil
            end

            it 'should pass in the context to #success as the first arg' do
               handler = double('handler')
               context = double('task_context')

               allow(Test::Task::AllHooks).to receive(:new).and_return(handler)

               allow(handler).to receive(:run)
               expect(handler).to receive(:success).with(context, anything, anything)

               worker = TaskWorker.new(task: task, queue: queue)
               worker.work(context: context)
            end

            it 'should pass in the queue logger to #success as the second arg' do
               handler = double('handler')
               logger  = Logger.new(StringIO.new)

               allow(Test::Task::AllHooks).to receive(:new).and_return(handler)

               allow(handler).to receive(:run)
               expect(handler).to receive(:success).with(anything, logger, anything)

               worker = TaskWorker.new(task: task, queue: queue)

               worker.work(logger: logger)
            end

            it 'should pass the result of #run to #success as the third arg' do
               handler = double('handler')
               result  = double('run result')

               allow(Test::Task::AllHooks).to receive(:new).and_return(handler)

               allow(handler).to receive(:run).and_return(result)
               expect(handler).to receive(:success).with(anything, anything, result)

               worker = TaskWorker.new(task: task, queue: queue)
               worker.work
            end

            it 'should log #success at debug level' do
               logger    = double('logger')
               data_yaml = YAML.dump(double('text'))

               worker = TaskWorker.new(queue: queue,
                                       task:  Task.new(last_fail_at: double('failtime'),
                                                       data:         data_yaml))

               expect(logger).to receive(:debug).with("Task completed: #{Test::Task::AllHooks} [#{data_yaml}]")

               worker.work(logger: logger)
            end
         end

         context 'fail hook' do
            it 'should #fail when #run errors' do
               handler = Test::Task::Fail.new

               allow(Test::Task::Fail).to receive(:new).and_return(handler)

               expect(handler).to receive(:fail)

               worker = TaskWorker.new(task: task, queue: fail_queue)
               worker.work
            end

            it 'should #fail when #run duration exceeds timeout and provide a timeout error' do
               handler = Test::Task::Fail.new
               timeout = 0.1 # can't be 0. timeout doesn't actually do timeout stuff if given 0
               allow(handler).to receive(:run) do
                  sleep(timeout + 0.1)
               end
               allow(Test::Task::Fail).to receive(:new).and_return(handler)

               timeout_queue = Procrastinator::Queue.new(name:       :timeout_queue,
                                                         task_class: Test::Task::Fail,
                                                         timeout:    timeout)

               expect(handler).to receive(:fail).with(anything, anything, Timeout::Error)

               worker = TaskWorker.new(task: task, queue: timeout_queue)
               worker.work
            end

            it 'should call #fail if nil max_attempts given and #run errors' do
               handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(handler)

               allow(handler).to receive(:run).and_raise('fake error')

               unlimited_queue = Procrastinator::Queue.new(name:         :unlimited_queue,
                                                           task_class:   Test::Task::Fail,
                                                           max_attempts: nil)

               expect(handler).to receive(:fail)

               worker = TaskWorker.new(task: task, queue: unlimited_queue)
               worker.work
            end

            it 'should NOT #fail when #success errors' do
               handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(handler)

               allow(handler).to receive(:run)
               allow(handler).to receive(:success).and_raise('testing success block error handling')

               expect(handler).to_not receive(:fail)

               worker = TaskWorker.new(task: task, queue: fail_queue)
               worker.work
            end

            it 'should NOT call #fail if calling #final_fail' do
               final_queue = Procrastinator::Queue.new(name:         :final_queue,
                                                       task_class:   Test::Task::Fail,
                                                       max_attempts: 0)

               handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(handler)

               allow(handler).to receive(:run).and_raise('fake error')
               allow(handler).to receive(:final_fail)
               expect(handler).to_not receive(:fail)

               worker = TaskWorker.new(task: task, queue: final_queue)
               worker.work
            end

            it 'should handle errors from task handler #fail' do
               handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(handler)

               err = 'fail error'

               allow(handler).to receive(:run).and_raise('run error')
               allow(handler).to receive(:fail).and_raise(err)

               worker = TaskWorker.new(task: task, queue: fail_queue)

               expect {worker.work}.to output("Fail hook error: #{err}\n").to_stderr
            end

            it 'should do nothing if the task handler does not include #fail' do
               worker = TaskWorker.new(task: task, queue: fail_queue)

               expect {worker.work}.to_not output.to_stderr
            end

            it 'should record the most recent failure time' do
               start_time = Time.now

               Timecop.freeze(start_time) do
                  delay = 100

                  fail_handler = Test::Task::Fail.new
                  allow(Test::Task::Fail).to receive(:new).and_return(fail_handler)

                  allow(fail_handler).to receive(:run) do
                     Timecop.travel(delay)
                     raise 'fake error'
                  end

                  worker = TaskWorker.new(task: task, queue: fail_queue)

                  worker.work

                  expect(worker.last_fail_at).to eq start_time.to_i + delay
               end
            end

            it 'should reschedule for the future' do
               worker = TaskWorker.new(task:  Task.new(run_at:         0,
                                                       initial_run_at: 0),
                                       queue: fail_queue)
               worker.work

               expect(worker.run_at).to be > worker.initial_run_at
            end

            it 'should reschedule on an increasing basis' do
               queue = Procrastinator::Queue.new(name:         :reschedule_queue,
                                                 task_class:   Test::Task::Fail,
                                                 max_attempts: 4)

               worker = TaskWorker.new(task:  Task.new(run_at: 0),
                                       queue: queue)

               (1..3).each do |i|
                  previous_time = worker.run_at

                  worker.work

                  expected_time = previous_time + (30 + (i ** 4))

                  actual_time = worker.run_at

                  expect(actual_time).to eq expected_time
               end
            end

            it 'should NOT reschedule when run_at is nil' do
               worker = TaskWorker.new(task:  Task.new(run_at: nil),
                                       queue: fail_queue)
               worker.work

               expect(worker.run_at).to be_nil
            end

            it 'should record the error and trace in last_error' do
               worker = TaskWorker.new(task: task, queue: fail_queue)
               worker.work

               expect(worker.last_error).to start_with 'Task failed: '
               expect(worker.last_error).to include 'derp' # message from the FailTask
               expect(worker.last_error).to match /(.*\n)+/ # poor version of checking for backtrace, but it works for now
            end

            it 'should pass in the task handler context to #fail as first arg' do
               fail_handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(fail_handler)

               err = StandardError.new('fake error')
               allow(fail_handler).to receive(:run).and_raise(err)

               context = double('task_context')
               expect(fail_handler).to receive(:fail).with(context, anything, anything)

               worker = TaskWorker.new(task: task, queue: fail_queue)
               worker.work(context: context)
            end

            it 'should pass in the queue logger to #fail as second arg' do
               fail_handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(fail_handler)

               err = StandardError.new('fake error')
               allow(fail_handler).to receive(:run).and_raise(err)

               logger = Logger.new(StringIO.new)
               expect(fail_handler).to receive(:fail).with(anything, logger, anything)

               worker = TaskWorker.new(task: task, queue: fail_queue)
               worker.work(logger: logger)
            end

            it 'should pass in the error to #fail as third arg' do
               fail_handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(fail_handler)

               err = StandardError.new('fake error')
               allow(fail_handler).to receive(:run).and_raise(err)

               expect(fail_handler).to receive(:fail).with(anything, anything, err)

               worker = TaskWorker.new(task: task, queue: fail_queue)
               worker.work
            end

            it 'should log #fail at debug level' do
               data          = double('data')
               handler       = double('handler')
               handler_class = double('handler class', new: handler)

               allow(handler).to receive(:run).and_raise('derp')

               logger = Logger.new(StringIO.new)

               queue = Procrastinator::Queue.new(name: :test, task_class: handler_class)

               worker = TaskWorker.new(task: Task.new(data: YAML.dump(data)), queue: queue)

               expect(logger).to receive(:debug).with("Task failed: #{queue.name} with #{YAML.dump(data)}")

               worker.work(logger: logger)
            end
         end

         context 'final_fail hook' do
            it 'should call #final_fail if #run errors more than given max_attempts' do
               max_attempts = 3

               handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(handler)

               overfail_queue = Procrastinator::Queue.new(name:         :overfail_queue,
                                                          task_class:   Test::Task::Fail,
                                                          max_attempts: max_attempts)

               worker = TaskWorker.new(task: task, queue: overfail_queue)

               expect(handler).to receive(:final_fail)

               max_attempts.times do
                  worker.work
               end
            end

            it 'should call #final_fail when the expiry time has passed' do
               (0..3).each do |i|
                  task = Test::Task::Fail.new
                  allow(Test::Task::Fail).to receive(:new).and_return(task)

                  expect(task).to receive(:final_fail).with(anything, anything, satisfy do |arg|
                     arg.is_a?(TaskExpiredError) && arg.message == "task is over its expiry time of #{i}"
                  end)

                  worker = TaskWorker.new(queue: fail_queue,
                                          task:  Task.new(expire_at: i))
                  worker.work
               end
            end

            it 'should NOT error or call #final_fail if nil max_attempts given' do
               handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(handler)

               unlimited_queue = Procrastinator::Queue.new(name:         :unlimited_queue,
                                                           task_class:   Test::Task::Fail,
                                                           max_attempts: nil)

               worker = TaskWorker.new(task: task, queue: unlimited_queue)

               expect(handler).to_not receive(:final_fail)

               worker.work
            end

            it 'should handle errors from #final_fail' do
               handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(handler)

               err = 'final fail error'

               allow(handler).to receive(:final_fail).and_raise(err)

               worker = TaskWorker.new(task: task, queue: final_fail_queue)

               expect do
                  worker.work
               end.to output("Final_fail hook error: #{err}\n").to_stderr
            end

            it 'should do nothing if the task does not include #final_fail' do
               worker = TaskWorker.new(task: task, queue: final_fail_queue)

               expect do
                  worker.work
               end.to_not output.to_stderr
            end

            it 'should record the final failure time' do
               fail_handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(fail_handler)

               start_time = Time.now
               delay      = 100

               Timecop.freeze(start_time) do
                  allow(fail_handler).to receive(:run) do
                     Timecop.travel(delay)
                     raise 'fake error'
                  end

                  worker = TaskWorker.new(task: task, queue: final_fail_queue)
                  worker.work

                  expect(worker.last_fail_at).to eq start_time.to_i + delay
               end
            end

            it 'should mark the task as permanently failed' do
               worker = TaskWorker.new(task: task, queue: final_fail_queue)
               worker.work

               expect(worker.run_at).to be nil
            end

            it 'should record that the expiry time has passed with trace' do
               worker = TaskWorker.new(queue: queue, task: Task.new(expire_at: 0))
               worker.work

               expect(worker.last_error).to start_with 'Task expired: '
               expect(worker.last_error).to match /(.*\n)+/ # poor version of checking for backtrace, but it works for now
            end

            it 'should record the error and trace in last_error' do
               worker = TaskWorker.new(task: task, queue: final_fail_queue)
               worker.work

               expect(worker.last_error).to start_with 'Task failed too many times: '
               expect(worker.last_error).to match /(.*\n)+/ # poor version of checking for backtrace, but it works for now
            end

            it 'should pass in the context to #final_fail as the first arg' do
               handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(handler)

               context = double('task_context')

               expect(handler).to receive(:final_fail).with(context, anything, anything)

               worker = TaskWorker.new(task: task, queue: final_fail_queue)
               worker.work(context: context)
            end

            it 'should pass in the queue logger to #final_fail as the second arg' do
               handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(handler)

               logger = Logger.new(StringIO.new)

               expect(handler).to receive(:final_fail).with(anything, logger, anything)

               worker = TaskWorker.new(task: task, queue: final_fail_queue)
               worker.work(logger: logger)
            end

            it 'should pass in the error to #final_fail as the third arg' do
               handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(handler)

               err = StandardError.new('fake error')
               allow(handler).to receive(:run).and_raise(err)

               expect(handler).to receive(:final_fail).with(anything, anything, err)

               worker = TaskWorker.new(task: task, queue: final_fail_queue)
               worker.work
            end

            it 'should log #final_fail at debug level' do
               handler = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(handler)

               err    = StandardError.new('fake error')
               logger = Logger.new(StringIO.new)

               allow(handler).to receive(:run).and_raise(err)

               worker = TaskWorker.new(task: task, queue: final_fail_queue)

               expect(logger).to receive(:debug).with("Task failed permanently: #{YAML.dump(handler)}")

               worker.work(logger: logger)
            end
         end
      end

      describe '#to_h' do
         it 'should return the task hash' do
            run_at         = double('run_at', to_i: double('run_at_i'))
            initial_run_at = double('initial_run_at', to_i: double('initial_run_at_i'))
            expire_at      = double('expire_at', to_i: double('expire_at_i'))

            task = Task.new(id:             double('id'),
                            attempts:       double('attempts'),
                            last_fail_at:   double('last_fail_at'),
                            last_error:     double('last_error'),
                            data:           YAML.dump(double('data')),
                            initial_run_at: initial_run_at,
                            run_at:         run_at,
                            expire_at:      expire_at)

            worker = TaskWorker.new(task: task, queue: queue)


            expect(worker.to_h).to eq(task.to_h)
         end
      end
   end
end