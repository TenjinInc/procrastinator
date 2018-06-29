require 'spec_helper'

module Procrastinator
   describe TaskWorker do
      let(:queue) {Procrastinator::Queue.new(name: :test_queue, task_class: Test::Task::AllHooks, max_attempts: 2)}
      let(:fail_queue) {Procrastinator::Queue.new(name: :fail_queue, task_class: Test::Task::Fail)}
      let(:final_fail_queue) {Procrastinator::Queue.new(name: :fail_queue, task_class: Test::Task::Fail, max_attempts: 0)}

      describe '#inititalize' do
         let(:task) {double('task', run: nil)}

         it 'should unpack data parameter' do
            task_data = double('task', run: nil)
            task_yml  = YAML.dump(task_data)
            task      = Test::Task::AllHooks.new

            allow(Test::Task::AllHooks).to receive(:new).and_return(task)
            allow(YAML).to receive(:load).with(task_yml).and_return(task_data)

            worker = TaskWorker.new(queue: queue, data: task_yml)

            expect(worker.data).to eq task_data
         end

         it 'should convert non-nil run_at, initial_run at, and expire_at to ints' do
            now = Time.now

            worker = TaskWorker.new(queue: queue, run_at: now, initial_run_at: now, expire_at: now)

            expect(worker.run_at).to eq now.to_i
            expect(worker.initial_run_at).to eq now.to_i
            expect(worker.expire_at).to eq now.to_i
         end

         # nil run_at means that it should never be run. Used for final_fail marking
         it 'should NOT convert nil run_at to int' do
            worker = TaskWorker.new(queue: queue, run_at: nil)

            expect(worker.run_at).to eq nil
         end

         # so that it doesn't insta-expire
         it 'should NOT convert nil expire_at to int' do
            worker = TaskWorker.new(queue: queue, expire_at: nil)

            expect(worker.expire_at).to eq nil
         end

         it 'should complain when no queue is given' do
            expect do
               TaskWorker.new
            end.to raise_error(ArgumentError, 'missing keyword: queue')
         end

         it 'should complain if task does not support #run' do
            task = double('BadTaskClass', new: double('taskInstance'))

            queue = Procrastinator::Queue.new(name: :test, task_class: task)

            expect do
               TaskWorker.new(queue: queue)
            end.to raise_error(MalformedTaskError, "task #{task.class} does not support #run method")
         end

         it 'should default nil attempts to 0' do
            worker = TaskWorker.new(queue: queue, attempts: nil)
            expect(worker.attempts).to be 0
         end

         it 'should pass in the data to the task initialization' do
            data     = double('task data')
            task_yml = YAML.dump(data)

            allow(YAML).to receive(:load).with(task_yml).and_return(data)

            TaskWorker.new(queue: queue, data: task_yml)
         end

         it 'should pass in the data to the task initialization' do
            data     = double('task data')
            task_yml = YAML.dump(data)

            allow(YAML).to receive(:load).with(task_yml).and_return(data)

            TaskWorker.new(queue: queue, data: task_yml)
         end
      end

      describe '#work' do

         context 'run hook' do
            it 'should call task #run' do
               task = double('task')

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               expect(task).to receive(:run)
               allow(task).to receive(:success)

               worker = TaskWorker.new(queue: queue)

               worker.work
            end

            it 'should increase number of attempts when #run is called' do
               task = double('task')

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               allow(task).to receive(:run)
               allow(task).to receive(:success)

               worker = TaskWorker.new(queue: queue)

               (1..3).each do |i|
                  worker.work
                  expect(worker.attempts).to eq i
               end
            end

            it 'should NOT call #run when the expiry time has passed' do
               task = double('task')

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               expect(task).to_not receive(:run)

               worker = TaskWorker.new(queue: queue, expire_at: 0)
               worker.work
            end

            it 'should pass in the context to #success as the first arg' do
               task    = double('task')
               context = double('task_context')

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               expect(task).to receive(:run).with(context, anything)
               allow(task).to receive(:success)

               worker = TaskWorker.new(queue: queue)
               worker.work(context: context)
            end

            it 'should pass in the queue logger to #success as the second arg' do
               task   = double('task')
               logger = Logger.new(StringIO.new)

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               expect(task).to receive(:run).with(anything, logger)
               allow(task).to receive(:success)

               worker = TaskWorker.new(queue: queue)
               worker.work(logger: logger)
            end
         end

         context 'success hook' do
            it 'should call task #success when #run completes without error' do
               task = double('task')

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               allow(task).to receive(:run)
               expect(task).to receive(:success)

               worker = TaskWorker.new(queue: queue)

               worker.work
            end

            it 'should NOT call task #success when #run errors' do
               task = Test::Task::Fail.new

               expect(task).to_not receive(:success)
               allow(task).to receive(:fail)

               allow(Test::Task::Fail).to receive(:new).and_return(task)

               worker = TaskWorker.new(queue: queue)

               worker.work
            end

            it 'should complain to stderr when #success errors' do
               task = Test::Task::AllHooks.new
               err  = 'testing success block error handling'

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               allow(task).to receive(:success).and_raise(err)

               worker = TaskWorker.new(queue: queue)

               expect {worker.work}.to output("Success hook error: #{err}\n").to_stderr
            end

            it 'should do nothing if the task does not include #success' do
               queue = Procrastinator::Queue.new(name: :run_only, task_class: Test::Task::RunOnly)

               worker = TaskWorker.new(queue: queue)

               expect {worker.work}.to_not output.to_stderr
            end

            it 'should blank the error message' do
               worker = TaskWorker.new(queue: queue, last_error: 'derp')

               worker.work

               expect(worker.last_error).to be nil
            end

            it 'should blank the error time' do
               worker = TaskWorker.new(queue: queue, last_fail_at: double('failtime'))

               worker.work

               expect(worker.last_fail_at).to be nil
            end

            it 'should pass in the context to #success as the first arg' do
               task    = double('task')
               context = double('task_context')

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               allow(task).to receive(:run)
               expect(task).to receive(:success).with(context, anything, anything)

               worker = TaskWorker.new(queue: queue)
               worker.work(context: context)
            end

            it 'should pass in the queue logger to #success as the second arg' do
               task   = double('task')
               logger = Logger.new(StringIO.new)

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               allow(task).to receive(:run)
               expect(task).to receive(:success).with(anything, logger, anything)

               worker = TaskWorker.new(queue: queue)

               worker.work(logger: logger)
            end

            it 'should pass the result of #run to #success as the third arg' do
               task   = double('task')
               result = double('run result')

               allow(Test::Task::AllHooks).to receive(:new).and_return(task)

               allow(task).to receive(:run).and_return(result)
               expect(task).to receive(:success).with(anything, anything, result)

               worker = TaskWorker.new(queue: queue)
               worker.work
            end

            it 'should log #success at debug level' do
               logger    = double('logger')
               data      = double('text')
               data_yaml = YAML.dump(data)

               worker = TaskWorker.new(queue: queue, last_fail_at: double('failtime'),
                                       data:  data_yaml)

               expect(logger).to receive(:debug).with("Task completed: #{Test::Task::AllHooks} [#{data}]")

               worker.work(logger: logger)
            end
         end

         context 'fail hook' do
            it 'should #fail when #run errors' do
               task = Test::Task::Fail.new

               allow(Test::Task::Fail).to receive(:new).and_return(task)

               expect(task).to receive(:fail)

               worker = TaskWorker.new(queue: fail_queue)
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

               expect(task).to receive(:fail).with(anything, anything, Timeout::Error)

               worker = TaskWorker.new(queue: timeout_queue)
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

               worker = TaskWorker.new(queue: unlimited_queue)
               worker.work
            end

            it 'should NOT #fail when #success errors' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               allow(task).to receive(:run)
               allow(task).to receive(:success).and_raise('testing success block error handling')

               expect(task).to_not receive(:fail)

               worker = TaskWorker.new(queue: fail_queue)
               worker.work
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

               worker = TaskWorker.new(queue: final_queue)
               worker.work
            end

            it 'should handle errors from task #fail' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               err = 'fail error'

               allow(task).to receive(:run).and_raise('run error')
               allow(task).to receive(:fail).and_raise(err)

               worker = TaskWorker.new(queue: fail_queue)

               expect {worker.work}.to output("Fail hook error: #{err}\n").to_stderr
            end

            it 'should do nothing if the task does not include #fail' do
               worker = TaskWorker.new(queue: fail_queue)

               expect {worker.work}.to_not output.to_stderr
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

                  worker = TaskWorker.new(queue: fail_queue)

                  worker.work

                  expect(worker.last_fail_at).to eq start_time.to_i + delay
               end
            end

            it 'should reschedule for the future' do
               worker = TaskWorker.new(run_at:         0,
                                       initial_run_at: 0,
                                       queue:          fail_queue)
               worker.work

               expect(worker.run_at).to be > worker.initial_run_at
            end

            it 'should reschedule on an increasing basis' do
               queue = Procrastinator::Queue.new(name:         :reschedule_queue,
                                                 task_class:   Test::Task::Fail,
                                                 max_attempts: 4)

               worker = TaskWorker.new(queue: queue, run_at: 0)

               (1..3).each do |i|
                  previous_time = worker.run_at

                  worker.work

                  expected_time = previous_time + (30 + (i ** 4))

                  actual_time = worker.run_at

                  expect(actual_time).to eq expected_time
               end
            end

            it 'should NOT reschedule when run_at is nil' do
               worker = TaskWorker.new(run_at: nil, queue: fail_queue)
               worker.work

               expect(worker.run_at).to be_nil
            end

            it 'should record the error and trace in last_error' do
               worker = TaskWorker.new(queue: fail_queue)
               worker.work

               expect(worker.last_error).to start_with 'Task failed: '
               expect(worker.last_error).to include 'derp' # message from the FailTask
               expect(worker.last_error).to match /(.*\n)+/ # poor version of checking for backtrace, but it works for now
            end

            it 'should pass in the task context to #fail as first arg' do
               fail_task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(fail_task)

               err = StandardError.new('fake error')
               allow(fail_task).to receive(:run).and_raise(err)

               context = double('task_context')
               expect(fail_task).to receive(:fail).with(context, anything, anything)

               worker = TaskWorker.new(queue: fail_queue)
               worker.work(context: context)
            end

            it 'should pass in the queue logger to #fail as second arg' do
               fail_task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(fail_task)

               err = StandardError.new('fake error')
               allow(fail_task).to receive(:run).and_raise(err)

               logger = Logger.new(StringIO.new)
               expect(fail_task).to receive(:fail).with(anything, logger, anything)

               worker = TaskWorker.new(queue: fail_queue)
               worker.work(logger: logger)
            end

            it 'should pass in the error to #fail as third arg' do
               fail_task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(fail_task)

               err = StandardError.new('fake error')
               allow(fail_task).to receive(:run).and_raise(err)

               expect(fail_task).to receive(:fail).with(anything, anything, err)

               worker = TaskWorker.new(queue: fail_queue)
               worker.work
            end

            it 'should log #fail at debug level' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               logger = Logger.new(StringIO.new)

               worker = TaskWorker.new(queue: fail_queue)

               expect(logger).to receive(:debug).with("Task failed: #{YAML.dump(task)}")

               worker.work(logger: logger)
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

               worker = TaskWorker.new(queue: overfail_queue)

               expect(task).to receive(:final_fail)

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

                  worker = TaskWorker.new(queue:     fail_queue,
                                          expire_at: i)
                  worker.work
               end
            end

            it 'should NOT error or call #final_fail if nil max_attempts given' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               unlimited_queue = Procrastinator::Queue.new(name:         :unlimited_queue,
                                                           task_class:   Test::Task::Fail,
                                                           max_attempts: nil)

               worker = TaskWorker.new(queue: unlimited_queue)

               expect(task).to_not receive(:final_fail)

               worker.work
            end

            it 'should handle errors from #final_fail' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               err = 'final fail error'

               allow(task).to receive(:final_fail).and_raise(err)

               worker = TaskWorker.new(queue: final_fail_queue)

               expect do
                  worker.work
               end.to output("Final_fail hook error: #{err}\n").to_stderr
            end

            it 'should do nothing if the task does not include #final_fail' do
               worker = TaskWorker.new(queue: final_fail_queue)

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

                  worker = TaskWorker.new(queue: final_fail_queue)
                  worker.work

                  expect(worker.last_fail_at).to eq start_time.to_i + delay
               end
            end

            it 'should mark the task as permanently failed' do
               worker = TaskWorker.new(queue: final_fail_queue)
               worker.work

               expect(worker.run_at).to be nil
            end

            it 'should record that the expiry time has passed with trace' do
               worker = TaskWorker.new(queue: queue, expire_at: 0)
               worker.work

               expect(worker.last_error).to start_with 'Task expired: '
               expect(worker.last_error).to match /(.*\n)+/ # poor version of checking for backtrace, but it works for now
            end

            it 'should record the error and trace in last_error' do
               worker = TaskWorker.new(queue: final_fail_queue)
               worker.work

               expect(worker.last_error).to start_with 'Task failed too many times: '
               expect(worker.last_error).to match /(.*\n)+/ # poor version of checking for backtrace, but it works for now
            end

            it 'should pass in the context to #final_fail as the first arg' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               context = double('task_context')

               expect(task).to receive(:final_fail).with(context, anything, anything)

               worker = TaskWorker.new(queue: final_fail_queue)
               worker.work(context: context)
            end

            it 'should pass in the queue logger to #final_fail as the second arg' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               logger = Logger.new(StringIO.new)

               expect(task).to receive(:final_fail).with(anything, logger, anything)

               worker = TaskWorker.new(queue: final_fail_queue)
               worker.work(logger: logger)
            end

            it 'should pass in the error to #final_fail as the third arg' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               err = StandardError.new('fake error')
               allow(task).to receive(:run).and_raise(err)

               expect(task).to receive(:final_fail).with(anything, anything, err)

               worker = TaskWorker.new(queue: final_fail_queue)
               worker.work
            end

            it 'should log #final_fail at debug level' do
               task = Test::Task::Fail.new
               allow(Test::Task::Fail).to receive(:new).and_return(task)

               err    = StandardError.new('fake error')
               logger = Logger.new(StringIO.new)

               allow(task).to receive(:run).and_raise(err)

               worker = TaskWorker.new(queue: final_fail_queue)

               expect(logger).to receive(:debug).with("Task failed permanently: #{YAML.dump(task)}")

               worker.work(logger: logger)
            end
         end
      end

      describe '#successful?' do
         it 'should return true when #run completes without error' do
            worker = TaskWorker.new(queue: queue)
            worker.work

            expect(worker.successful?).to be true
         end

         it 'should return false if #run failed' do
            worker = TaskWorker.new(queue: fail_queue)

            worker.work

            expect(worker.successful?).to be false
         end

         it 'should return false if final failure' do
            worker = TaskWorker.new(queue: final_fail_queue)

            worker.work

            expect(worker.successful?).to be false
         end

         it 'should return false if the task is expired' do
            worker = TaskWorker.new(queue: queue, expire_at: 0)

            worker.work

            expect(worker.successful?).to be false
         end

         it 'should complain if the task has not been run yet' do
            worker = TaskWorker.new(queue: queue)

            expect {worker.successful?}.to raise_error(RuntimeError, 'you cannot check for success before running #work')
         end

         it 'should NOT complain if the task is expired' do
            worker = TaskWorker.new(queue: queue, expire_at: 0)

            expect {worker.successful?}.to_not raise_error
         end
      end

      describe '#expired?' do
         let(:now) {now = Time.now}

         it 'should return true when the expiry date has passed' do
            worker = TaskWorker.new(queue: queue, expire_at: now.to_i - 1)

            Timecop.freeze(now) do
               expect(worker.expired?).to be true
            end
         end

         it 'should return false when the expiry date is not set' do
            worker = TaskWorker.new(queue: queue, expire_at: nil)

            Timecop.freeze(now) do
               expect(worker.expired?).to be false
            end
         end

         it 'should return false when the expiry date has not passed' do
            worker = TaskWorker.new(queue: queue, expire_at: now.to_i)

            Timecop.freeze(now) do
               expect(worker.expired?).to be false
            end
         end
      end

      describe '#to_hash' do
         it 'should return the properties as a hash' do
            basics = {
                  id:           double('id'),
                  attempts:     double('attempts'),
                  last_fail_at: double('last_fail_at'),
                  last_error:   double('last_error'),
                  data:         YAML.dump(double('data'))
            }

            run_at         = double('run_at', to_i: double('run_at_i'))
            initial_run_at = double('initial_run_at', to_i: double('initial_run_at_i'))
            expire_at      = double('expire_at', to_i: double('expire_at_i'))

            worker = TaskWorker.new(basics.merge(initial_run_at: initial_run_at,
                                                 run_at:         run_at,
                                                 expire_at:      expire_at,
                                                 queue:          queue))


            expect(worker.task_hash).to eq(basics.merge(initial_run_at: initial_run_at.to_i,
                                                        run_at:         run_at.to_i,
                                                        expire_at:      expire_at.to_i))
         end
      end
   end
end