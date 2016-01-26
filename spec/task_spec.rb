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

      it 'should complain if strategy does not support #run' do
         expect do
            Procrastinator::Task.new(strategy: double('BadStrat'), queue: :some_queue)
         end.to raise_error(Procrastinator::BadStrategyError, 'given strategy does not support #run method')
      end

      it 'should complain when no strategy is given' do
         expect { Procrastinator::Task.new(queue: :some_queue) }.to raise_error(ArgumentError, 'missing keyword: strategy')
      end
   end
end
