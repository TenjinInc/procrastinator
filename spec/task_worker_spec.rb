require 'spec_helper'

describe Procrastinator::TaskWorker do
   let(:queue) { double('queue', timeout: 0.1) }

   describe '#inititalize' do
      let(:task) { double('Some task', run: 5) }

      context('run_at') do
         it 'should accept run_at parameter' do
            [double('time1'), double('time2')].each do |time|
               worker = Procrastinator::TaskWorker.new(run_at: time, queue: :test_queue, task: task)

               expect(worker.run_at).to eq time
            end
         end

         it 'should default run_at to now' do
            now = Time.now

            Timecop.freeze(now) do
               worker = Procrastinator::TaskWorker.new(queue: :test_queue, task: task)

               expect(worker.run_at).to eq now
            end
         end
      end

      context('queue') do
         it 'should accept queue parameter' do
            [:test_queue, :other_name].each do |queue|

               worker = Procrastinator::TaskWorker.new(queue: queue, task: task)

               expect(worker.queue).to eq queue
            end
         end

         it 'should complain when no queue is given' do
            expect { Procrastinator::TaskWorker.new(task: :some_task) }.to raise_error(ArgumentError, 'missing keyword: queue')
         end
      end

      context 'task' do
         it 'should accept task parameter' do
            worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

            expect(worker.task).to eq task
         end

         it 'should complain when no task is given' do
            expect { Procrastinator::TaskWorker.new(queue: queue) }.to raise_error(ArgumentError, 'missing keyword: task')
         end

         it 'should complain if task does not support #run' do
            expect do
               Procrastinator::TaskWorker.new(task: double('Badtask'), queue: queue)
            end.to raise_error(Procrastinator::MalformedTaskError, 'given task does not support #run method')
         end
      end
   end

   describe '#work' do
      it 'should call task #run' do
         task = double('task')

         expect(task).to receive(:run)
         allow(task).to receive(:success)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         worker.work
      end

      it 'should call task #success when #run completes without error' do
         task = double('task')

         allow(task).to receive(:run)
         expect(task).to receive(:success)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         worker.work
      end

      it 'should not call task #success when #run errors' do
         task = double('task')

         allow(task).to receive(:run).and_raise('fake error')
         expect(task).to_not receive(:success)
         allow(task).to receive(:fail)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         worker.work
      end

      it 'should not call task #fail when #success errors' do
         task = double('task')

         allow(task).to receive(:run)
         allow(task).to receive(:success).and_raise('success block error')
         expect(task).to_not receive(:fail)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         worker.work
      end

      it 'should complain to stderr when #success errors' do
         task = double('task')
         err  ='success block error'

         allow(task).to receive(:run)
         allow(task).to receive(:success).and_raise(err)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         expect { worker.work }.to output("Success hook error: #{err}\n").to_stderr
      end

      it 'should call #fail when #run errors' do
         task = double('task')

         allow(task).to receive(:run).and_raise('fake error')

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         expect(task).to receive(:fail)

         worker.work
      end

      it 'should call #fail when #run duration exceeds timeout' do
         task = double('task')

         allow(task).to receive(:run) do
            sleep(queue.timeout+0.1)
         end
         expect(task).to receive(:fail)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         worker.work
      end

      it 'should increase number of attempts when #run is called' do
         task = double('task')

         allow(task).to receive(:run)
         allow(task).to receive(:success)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         (1..3).each do |i|
            worker.work
            expect(worker.attempts).to eq i
         end
      end

      it 'should call #final_fail if #run errors more than given max_attempts' do
         task         = double('task')
         max_attempts = 3

         allow(task).to receive(:run).and_raise('fake error')
         allow(task).to receive(:fail)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         expect(task).to receive(:final_fail)

         begin
            (max_attempts + 1).times do
               worker.work(max_attempts: max_attempts)
            end
         rescue Procrastinator::FinalFailError
            # it complains, but that's not this test
         end
      end

      it 'should not call #fail if calling #final_fail' do
         task = double('task')

         allow(task).to receive(:run).and_raise('fake error')
         allow(task).to receive(:final_fail)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         expect(task).to_not receive(:fail) # this is the real expectation

         begin
            worker.work(max_attempts: 0)
         rescue Procrastinator::FinalFailError
            # it complains, but that's not this test
         end
      end

      it 'should call #fail if nil max_attempts given and #run errors' do
         task = double('task')

         allow(task).to receive(:run).and_raise('fake error')
         expect(task).to receive(:fail)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         worker.work(max_attempts: nil)
      end

      it 'should not error or call #final_fail if nil max_attempts given' do
         task = double('task')

         allow(task).to receive(:run).and_raise('fake error')
         allow(task).to receive(:fail)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         expect(task).to_not receive(:final_fail)

         worker.work(max_attempts: nil)
      end

      it 'should call #final_fail if #run errors more than given max_attempts' do
         task = double('task')

         allow(task).to receive(:run).and_raise('fake error')
         allow(task).to receive(:final_fail)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         expect { worker.work(max_attempts: 0) }.to raise_error(Procrastinator::FinalFailError)
      end

      it 'should handle errors from task #fail' do
         task = double('task')
         err  = 'fail error'

         allow(task).to receive(:run).and_raise('run error')
         allow(task).to receive(:fail).and_raise(err)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         expect { worker.work }.to output("Fail hook error: #{err}\n").to_stderr
      end

      it 'should handle errors from task #final_fail' do
         task = double('task')
         err  = 'final fail error'

         allow(task).to receive(:run).and_raise('run error')
         allow(task).to receive(:final_fail).and_raise(err)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         expect do
            begin
               worker.work(max_attempts: 0)
            rescue Procrastinator::FinalFailError
               # do nothing. this error is unimportant to the test
            end
         end.to output("Final_fail hook error: #{err}\n").to_stderr
      end

      it 'should do nothing if the task does not include #success' do
         task = double('task')

         allow(task).to receive(:run)

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         expect { worker.work }.to_not output.to_stderr
      end

      it 'should do nothing if the task does not include #fail' do
         task = double('task')

         allow(task).to receive(:run).and_raise('fake error')

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         expect { worker.work }.to_not output.to_stderr
      end

      it 'should do nothing if the task does not include #final_fail' do
         task = double('task')

         allow(task).to receive(:run).and_raise('fake error')

         worker = Procrastinator::TaskWorker.new(task: task, queue: queue)

         expect do
            begin
               worker.work(max_attempts: 0)
            rescue Procrastinator::FinalFailError
               # do nothing. this error is unimportant to the test
            end
         end.to_not output.to_stderr
      end
   end
end
