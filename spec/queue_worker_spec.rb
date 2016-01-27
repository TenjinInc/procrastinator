require 'spec_helper'

describe Procrastinator::QueueWorker do
   describe '#work' do

      describe '#initialize' do
         it 'should require a queue name to work on'
      end

      context 'worker idle' do
         it 'should use a defined sleep time' # user defined
         it 'should have a default sleep time' #ie between reads

         it 'should only take jobs from the given queue'
         it 'should scan for new items in the queue from persistence'
         it 'should add any new additions to the queue after reloading'
         it 'should lose any removals from the queue after reloading'
      end

      context 'run_at time passed' do
         it 'should call Task#run' do

            expect(subject).to receive(:run)
         end
      end

      context '#run succeeds' do
         it 'should delete the task'
      end

      context '#run failed' do
         it 'should sleep for the retry delay duration'
         it 'should reschedule on an increasing basis'


         it 'should #fail when #run errors' do
            t = Procrastinator.delay do |task|
               task.run do
                  raise('fake_error')
               end
            end

            expect(t).to receive(:fail)
         end
      end

      context '#run failed too many times' do
         it 'should #final_fail when #run fails more then max_fails'
         it 'should not #fail when #run fails more then max_fails'

         it 'should rescue if #final_fail errors' #TODO: and do what? puts to stderr maybe?
      end
   end
end

