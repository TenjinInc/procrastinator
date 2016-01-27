require 'spec_helper'

describe Procrastinator::QueueWorker do
   describe '#work' do

      describe '#initialize' do
         it 'should require a queue to work on'
      end

      what if a task has no queue?

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

