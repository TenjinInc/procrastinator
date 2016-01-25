require 'spec_helper'

describe Procrastinator::Task do
   it 'should accept run_at parameter' do
      now = Time.now

      Timecop.freeze(now) do
         task = Procrastinator::Task.new(run_at: now, queue: :test_queue)

         expect(task.run_at).to eq now
      end
   end

   it 'should default run_at to now' do
      now = Time.now

      Timecop.freeze(now) do
         task = Procrastinator::Task.new(queue: :test_queue)

         expect(task.run_at).to eq now
      end
   end

   it 'should accept queue parameter' do
      [:test_queue, :other_name].each do |queue|

         task = Procrastinator::Task.new(queue: queue)

         expect(task.queue).to eq queue
      end
   end

   it 'should complain when no queue is given' do
      expect { Procrastinator::Task.new }.to raise_error(ArgumentError, 'missing keyword: queue')
   end
end
