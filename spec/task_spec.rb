require 'spec_helper'

describe Procrastinator::Task do
   let(:strategy) { double('Some Strategy', run: 5) }

   context('run_at') do
      it 'should accept run_at parameter' do
         [double('time1'), double('time2')].each do |time|
            task = Procrastinator::Task.new(run_at: time, queue: :test_queue, strategy: strategy)

            expect(task.run_at).to eq time
         end
      end

      it 'should default run_at to now' do
         now = Time.now

         Timecop.freeze(now) do
            task = Procrastinator::Task.new(queue: :test_queue, strategy: strategy)

            expect(task.run_at).to eq now
         end
      end
   end

   context('queue') do
      it 'should accept queue parameter' do
         [:test_queue, :other_name].each do |queue|

            task = Procrastinator::Task.new(queue: queue, strategy: strategy)

            expect(task.queue).to eq queue
         end
      end

      it 'should complain when no queue is given' do
         expect { Procrastinator::Task.new(strategy: :some_strategy) }.to raise_error(ArgumentError, 'missing keyword: queue')
      end
   end

   context 'strategy' do
      it 'should accept strategy parameter' do
         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         expect(task.strategy).to eq strategy
      end

      it 'should complain when no strategy is given' do
         expect { Procrastinator::Task.new(queue: :some_queue) }.to raise_error(ArgumentError, 'missing keyword: strategy')
      end

      it 'should complain if strategy does not support #run' do
         expect do
            Procrastinator::Task.new(strategy: double('BadStrat'), queue: :some_queue)
         end.to raise_error(Procrastinator::BadStrategyError, 'given strategy does not support #run method')
      end

      it 'should call strategy #run when performing' do
         strategy = double('Strat')

         expect(strategy).to receive(:run)
         allow(strategy).to receive(:success)

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         task.perform
      end

      it 'should call strategy #success when #run completes without error' do
         strategy = double('Strat')

         allow(strategy).to receive(:run)
         expect(strategy).to receive(:success)

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         task.perform
      end

      it 'should not call strategy #success when #run errors' do
         strategy = double('Strat')

         allow(strategy).to receive(:run).and_raise('fake error')
         expect(strategy).to_not receive(:success)
         allow(strategy).to receive(:fail)

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         task.perform
      end

      it 'should not call strategy #fail when #success errors' do
         strategy = double('Strat')

         allow(strategy).to receive(:run)
         allow(strategy).to receive(:success).and_raise('success block error')
         expect(strategy).to_not receive(:fail)

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         task.perform
      end

      it 'should complain to stderr when #success errors' do
         strategy = double('Strat')
         err      ='success block error'

         allow(strategy).to receive(:run)
         allow(strategy).to receive(:success).and_raise(err)

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         expect { task.perform }.to output("Success hook error: #{err}\n").to_stderr
      end

      it 'should call #fail when #run errors' do
         strategy = double('Custom Strat')

         allow(strategy).to receive(:run).and_raise('fake error')

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         expect(strategy).to receive(:fail)

         task.perform
      end

      it 'should increase number of attempts when #run is called' do
         strategy = double('Custom Strat')

         allow(strategy).to receive(:run)
         allow(strategy).to receive(:success)

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         (1..3).each do |i|
            task.perform
            expect(task.attempts).to eq i
         end
      end

      it 'should call #final_fail if #run errors more than given max_attempts' do
         strategy     = double('Custom Strat')
         max_attempts = 3

         allow(strategy).to receive(:run).and_raise('fake error')
         allow(strategy).to receive(:fail)

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         expect(strategy).to receive(:final_fail)

         begin
            (max_attempts + 1).times do
               task.perform(max_attempts: max_attempts)
            end
         rescue Procrastinator::FinalFailError
            # it complains, but that's not this test
         end
      end

      it 'should not call #fail if calling #final_fail' do
         strategy = double('Custom Strat')

         allow(strategy).to receive(:run).and_raise('fake error')
         allow(strategy).to receive(:final_fail)

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         expect(strategy).to_not receive(:fail) # this is the real expectation

         begin
            task.perform(max_attempts: 0)
         rescue Procrastinator::FinalFailError
            # it complains, but that's not this test
         end
      end

      it 'should call #fail if nil max_attempts given and #run errors' do
         strategy = double('Custom Strat')

         allow(strategy).to receive(:run).and_raise('fake error')
         expect(strategy).to receive(:fail)

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         task.perform(max_attempts: nil)
      end

      it 'should not error or call #final_fail if nil max_attempts given' do
         strategy = double('Custom Strat')

         allow(strategy).to receive(:run).and_raise('fake error')
         allow(strategy).to receive(:fail)

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         expect(strategy).to_not receive(:final_fail)

         task.perform(max_attempts: nil)
      end

      it 'should call #final_fail if #run errors more than given max_attempts' do
         strategy = double('Strat')

         allow(strategy).to receive(:run).and_raise('fake error')
         allow(strategy).to receive(:final_fail)

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         expect { task.perform(max_attempts: 0) }.to raise_error(Procrastinator::FinalFailError)
      end

      it 'should handle errors from strategy #fail' do
         strategy = double('Strat')
         err      = 'fail error'

         allow(strategy).to receive(:run).and_raise('run error')
         allow(strategy).to receive(:fail).and_raise(err)

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         expect { task.perform }.to output("Fail hook error: #{err}\n").to_stderr
      end

      it 'should handle errors from strategy #final_fail' do
         strategy = double('Strat')
         err      = 'final fail error'

         allow(strategy).to receive(:run).and_raise('run error')
         allow(strategy).to receive(:final_fail).and_raise(err)

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         expect do
            begin
               task.perform(max_attempts: 0)
            rescue Procrastinator::FinalFailError
               # do nothing. this error is unimportant to the test
            end
         end.to output("Final_fail hook error: #{err}\n").to_stderr
      end

      it 'should do nothing if the strategy does not include #success' do
         strategy = double('Strat')

         allow(strategy).to receive(:run)

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         expect { task.perform }.to_not output.to_stderr
      end

      it 'should do nothing if the strategy does not include #fail' do
         strategy = double('Strat')

         allow(strategy).to receive(:run).and_raise('fake error')

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         expect { task.perform }.to_not output.to_stderr
      end

      it 'should do nothing if the strategy does not include #final_fail' do
         strategy = double('Strat')

         allow(strategy).to receive(:run).and_raise('fake error')

         task = Procrastinator::Task.new(strategy: strategy, queue: :some_queue)

         expect do
            begin
               task.perform(max_attempts: 0)
            rescue Procrastinator::FinalFailError
               # do nothing. this error is unimportant to the test
            end
         end.to_not output.to_stderr
      end
   end
end
