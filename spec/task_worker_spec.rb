require 'spec_helper'

module Procrastinator
   describe TaskWorker do
      describe '#inititalize' do
         let(:task) { double('Some task', run: 5) }

         it 'should accept run_at parameter' do
            [double('time1'), double('time2')].each do |time|
               worker = TaskWorker.new(run_at: time, task: task)

               expect(worker.run_at).to eq time
            end
         end

         it 'should default run_at to now' do
            now = Time.now

            Timecop.freeze(now) do
               worker = TaskWorker.new(task: task)

               expect(worker.run_at).to eq now
            end
         end

         # context('queue') do
         # it 'should accept timeout parameter' do
         #    (1..3).each do |t|
         #       worker = TaskWorker.new(timeout: t, task: task)
         #
         #       expect(worker.timeout).to eq t
         #    end
         # end
         #
         # it 'should accept max_attempts parameter' do
         #    (1..3).each do |i|
         #       worker = TaskWorker.new(max_attempts: i, task: task)
         #
         #       expect(worker.max_attempts).to eq i
         #    end
         # end
         # end

         it 'should complain when timeout is negative' do
            expect { TaskWorker.new(task: task, timeout: -1) }.to raise_error(ArgumentError, 'Timeout cannot be negative')
         end

         it 'should accept attempts' do
            (1..3).each do |attempts|

               worker = TaskWorker.new(attempts: attempts, task: task)

               expect(worker.attempts).to eq attempts
            end
         end

         it 'should accept task parameter' do
            worker = TaskWorker.new(task: task)

            expect(worker.task).to eq task
         end

         it 'should complain when no task is given' do
            expect { TaskWorker.new }.to raise_error(ArgumentError, 'missing keyword: task')
         end

         it 'should complain if task does not support #run' do
            expect do
               TaskWorker.new(task: double('Badtask'))
            end.to raise_error(MalformedTaskError, 'given task does not support #run method')
         end
      end

      describe '#work' do

         context 'run hook' do
            it 'should call task #run' do
               task = double('task')

               expect(task).to receive(:run)
               allow(task).to receive(:success)

               worker = TaskWorker.new(task: task)

               worker.work
            end

            it 'should increase number of attempts when #run is called' do
               task = double('task')

               allow(task).to receive(:run)
               allow(task).to receive(:success)

               worker = TaskWorker.new(task: task)

               (1..3).each do |i|
                  worker.work
                  expect(worker.attempts).to eq i
               end
            end
         end

         context 'success hook' do
            it 'should call task #success when #run completes without error' do
               task = double('task')

               allow(task).to receive(:run)
               expect(task).to receive(:success)

               worker = TaskWorker.new(task: task)

               worker.work
            end

            it 'should not call task #success when #run errors' do
               task = double('task')

               allow(task).to receive(:run).and_raise('fake error')
               expect(task).to_not receive(:success)
               allow(task).to receive(:fail)

               worker = TaskWorker.new(task: task)

               worker.work
            end

            it 'should complain to stderr when #success errors' do
               task = double('task')
               err  ='success block error'

               allow(task).to receive(:run)
               allow(task).to receive(:success).and_raise(err)

               worker = TaskWorker.new(task: task)

               expect { worker.work }.to output("Success hook error: #{err}\n").to_stderr
            end

            it 'should do nothing if the task does not include #success' do
               task = double('task')

               allow(task).to receive(:run)

               worker = TaskWorker.new(task: task)

               expect { worker.work }.to_not output.to_stderr
            end
         end

         context 'fail hook' do
            it 'should #fail when #run errors' do
               task = double('task')
               err  = StandardError.new('fake error')

               allow(task).to receive(:run).and_raise(err)

               worker = TaskWorker.new(task: task)

               expect(task).to receive(:fail).with(err)

               worker.work
            end

            it 'should #fail when #run duration exceeds timeout' do
               task    = double('task')
               timeout = 0.1 # can't be 0. timeout doesn't actually do timeout stuff if given 0

               allow(task).to receive(:run) do
                  sleep(timeout + 0.1)
               end
               expect(task).to receive(:fail).with(Timeout::Error)

               worker = TaskWorker.new(task: task, timeout: timeout)

               worker.work
            end

            it 'should call #fail if nil max_attempts given and #run errors' do
               task = double('task')

               allow(task).to receive(:run).and_raise('fake error')
               expect(task).to receive(:fail)

               worker = TaskWorker.new(task: task, max_attempts: nil)

               worker.work
            end

            it 'should not #fail when #success errors' do
               task = double('task')

               allow(task).to receive(:run)
               allow(task).to receive(:success).and_raise('success block error')
               expect(task).to_not receive(:fail)

               worker = TaskWorker.new(task: task)

               worker.work
            end

            it 'should not #fail if calling #final_fail' do
               task = double('task')

               allow(task).to receive(:run).and_raise('fake error')
               allow(task).to receive(:final_fail)

               worker = TaskWorker.new(task: task, max_attempts: 0)

               expect(task).to_not receive(:fail) # this is the real expectation

               worker.work
            end

            it 'should handle errors from task #fail' do
               task = double('task')
               err  = 'fail error'

               allow(task).to receive(:run).and_raise('run error')
               allow(task).to receive(:fail).and_raise(err)

               worker = TaskWorker.new(task: task)

               expect { worker.work }.to output("Fail hook error: #{err}\n").to_stderr
            end

            it 'should do nothing if the task does not include #fail' do
               task = double('task')

               allow(task).to receive(:run).and_raise('fake error')

               worker = TaskWorker.new(task: task)

               expect { worker.work }.to_not output.to_stderr
            end

            it 'should record the most recent failure time' do
               task       = double('task')
               start_time = Time.now
               delay      = 100

               Timecop.freeze(start_time) do
                  allow(task).to receive(:run) do
                     Timecop.travel(delay)
                     raise 'fake error'
                  end

                  worker = TaskWorker.new(task: task)

                  worker.work

                  expect(worker.last_fail_at).to eq start_time.to_i + delay
               end
            end
         end

         context 'final_fail hook' do
            it 'should call #final_fail if #run errors more than given max_attempts' do
               max_attempts = 3
               task         = double('task')
               err          = StandardError.new('fake error')

               allow(task).to receive(:run).and_raise(err)
               allow(task).to receive(:fail)

               worker = TaskWorker.new(task: task, max_attempts: max_attempts)

               expect(task).to receive(:final_fail).with(err)

               max_attempts.times do
                  worker.work
               end
            end

            it 'should not error or call #final_fail if nil max_attempts given' do
               task = double('task')

               allow(task).to receive(:run).and_raise('fake error')
               allow(task).to receive(:fail)

               worker = TaskWorker.new(task: task, max_attempts: nil)

               expect(task).to_not receive(:final_fail)

               worker.work
            end

            it 'should handle errors from #final_fail' do
               task = double('task')
               err  = 'final fail error'

               allow(task).to receive(:run).and_raise('run error')
               allow(task).to receive(:final_fail).and_raise(err)

               worker = TaskWorker.new(task: task, max_attempts: 0)

               expect do
                  begin
                     worker.work
                  rescue FinalFailError
                     # do nothing. this error is unimportant to the test
                  end
               end.to output("Final_fail hook error: #{err}\n").to_stderr
            end

            it 'should do nothing if the task does not include #final_fail' do
               task = double('task')

               allow(task).to receive(:run).and_raise('fake error')

               worker = TaskWorker.new(task: task, max_attempts: 0)

               expect do
                  begin
                     worker.work
                  rescue FinalFailError
                     # do nothing. this raise is intended and unimportant to the test
                  end
               end.to_not output.to_stderr
            end

            it 'should record the most final failure time' do
               task       = double('task')
               start_time = Time.now
               delay      = 100

               Timecop.freeze(start_time) do
                  allow(task).to receive(:run) do
                     Timecop.travel(delay)
                     raise 'fake error'
                  end

                  worker = TaskWorker.new(task: task, max_attempts: 0)

                  begin
                     worker.work
                  rescue FinalFailError
                     # do nothing. this raise is intended and unimportant to the test
                  end

                  expect(worker.last_fail_at).to eq start_time.to_i + delay
               end
            end
         end
      end

      describe '#final_fail?' do
         it 'should be true if no attempts remain' do
            task = double('task')

            allow(task).to receive(:run).and_raise('fake error')
            allow(task).to receive(:fail)

            worker = TaskWorker.new(task: task, attempts: 2, max_attempts: 3)

            worker.work # attempts should now go up to 3

            expect(worker.final_fail?).to be true
         end

         it 'should be false if attempts remain' do
            task = double('task')

            allow(task).to receive(:run).and_raise('fake error')
            allow(task).to receive(:fail)

            worker = TaskWorker.new(task: task, attempts: 1, max_attempts: 3)

            worker.work

            expect(worker.final_fail?).to be false
         end

         it 'should be false if nil max_attempts is given' do
            task = double('task')

            allow(task).to receive(:run).and_raise('fake error')
            allow(task).to receive(:fail)

            worker = TaskWorker.new(task: task, max_attempts: nil)

            worker.work

            expect(worker.final_fail?).to be false
         end
      end
   end
end