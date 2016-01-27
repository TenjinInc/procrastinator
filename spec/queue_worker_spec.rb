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

      it 'should accept a update_frequency' do
         (1..3).each do |t|
            queue = Procrastinator::QueueWorker.new(name: :queue, max_attempts: t)

            expect(queue.max_attempts).to eq t
         end
      end

      it 'should provide a default checking freq'
   end

   describe '#work' do

      # TODO: what if a task has no queue?

      context 'worker idle' do
         it 'should use a defined task reading frequency' # user defined
         it 'should have a default task reading frequency' #ie between reads

         it 'should only take jobs from the given queue'
         it 'should scan for new tasks that can be run immediately'
         it 'should add any new additions to the queue after reloading'
         it 'should lose any removals from the queue after reloading'
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

