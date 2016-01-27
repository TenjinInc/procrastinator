require 'spec_helper'

describe Procrastinator::QueueWorker do
   describe '#initialize' do
      it 'should require a name' do
         expect { Procrastinator::QueueWorker.new }.to raise_error(ArgumentError)
      end

      it 'should store name as symbol' do
         [:email, :cleanup, 'a name'].each do |name|
            queue = Procrastinator::QueueWorker.new(name: name)

            expect(queue.name).to eq name.to_s.gsub(/\s/, '_').to_sym
         end
      end

      it 'should require the name not be nil' do
         expect { Procrastinator::QueueWorker.new(name: nil) }.to raise_error(ArgumentError, 'Queue name may not be nil')
      end

      it 'should accept a timeout' do
         (1..3).each do |t|

            queue = Procrastinator::QueueWorker.new(name: :queue, timeout: t)

            expect(queue.timeout).to eq t
         end
      end

      it 'should provide default timeout' do
         queue = Procrastinator::QueueWorker.new(name: :queue)

         expect(queue.timeout).to eq Procrastinator::QueueWorker::DEFAULT_TIMEOUT
      end

      it 'should accept a max_attempts' do
         (1..3).each do |t|
            queue = Procrastinator::QueueWorker.new(name: :queue, max_attempts: t)

            expect(queue.max_attempts).to eq t
         end
      end

      it 'should provide default max_attempts' do
         queue = Procrastinator::QueueWorker.new(name: :queue)

         expect(queue.max_attempts).to eq Procrastinator::QueueWorker::DEFAULT_MAX_ATTEMPTS
      end

      it 'should accept a update_period' do
         (1..3).each do |i|
            queue = Procrastinator::QueueWorker.new(name: :queue, update_period: i)

            expect(queue.update_period).to eq i
         end
      end

      it 'should provide a default update_period' do
         queue = Procrastinator::QueueWorker.new(name: :queue)

         expect(queue.update_period).to eq Procrastinator::QueueWorker::DEFAULT_UPDATE_PERIOD
      end

      it 'should accept a max_tasks' do
         (1..3).each do |i|
            queue = Procrastinator::QueueWorker.new(name: :queue, max_tasks: i)

            expect(queue.max_tasks).to eq i
         end
      end

      it 'should provide a default max_tasks' do
         queue = Procrastinator::QueueWorker.new(name: :queue)

         expect(queue.max_tasks).to eq Procrastinator::QueueWorker::DEFAULT_MAX_TASKS
      end
   end

   describe '#work' do
      context 'worker idle' do
         it 'should update every update_period' # user defined

         it 'should only take jobs from the given queue'
         it 'should sort tasks by run_at' # make sure this is using a good algo for already sorted lists
         it 'should add any new additions to the queue after reloading'
         it 'should lose any removals from the queue after reloading'
         it 'should start a TaskWorker for each ready task'
         it 'should not start more TaskWorkers than max_tasks'
         it 'should not start a TaskWorker any unready tasks'
      end

      context 'TaskWorker succeeds' do
         it 'should delete the task'
      end

      context 'TaskWorker failed' do
         it 'should reschedule for the future'
         it 'should reschedule on an increasing basis'
      end

      context 'TaskWorker failed for the last time' do
         # to do: promote captain Piett to admiral


         it 'should mark the task as permanently failed' # maybe by blanking run_at?
      end
   end
end

