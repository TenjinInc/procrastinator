require 'spec_helper'

describe Procrastinator::Worker do
   describe '#work' do
      it 'should require a queue name to work on'
      it 'should require a queue-reading block' # ie how to read the queue table

      it 'should only take jobs from the specific queue'

      it 'should lock a job when it is working on it'
      it 'should unlock a job when it is not working on it'

      context 'worker idle' do
         it 'should use a defined sleep time' # user defined
         it 'should have a default sleep time' #ie between reads

         it 'should scan for new items in the queue from persistence'
         it 'should add any new additions to the queue after reloading'
         it 'should lose any removals from the queue after reloading'
      end

      context 'run_at passed' do
         it 'should call Task#run' do

            Procrastinator.define_queue(:email, max_fails: 3, timeout: 1000)

            Procrastinator.delay(run_at: Time.now + 10, queue: :email) do |task|
               task.job do

               end

               task.success do

               end

               task.fail do

               end

               task.final_fail do

               end
            end


            expect(subject).to receive(:run)
         end
      end


      context 'job succeeds' do
         it 'should #success when #run completes without error'
      end


      context 'job failed' do
         it 'should sleep for the retry delay duration'
         it 'should reschedule on an increasing basis'


         it 'should #fail when #job errors' do
            t = Procrastinator.delay do |task|
               task.run do
                  raise('fake_error')
               end
            end

            expect(t).to receive(:fail)
         end

         it 'should #fail if #job runs over timeout'

         it 'should rescue when #fail errors' #TODO: and do what? puts to stderr maybe?
      end

      context 'job failed too many times' do
         it 'should #final_fail when #run fails more then max_fails'
         it 'should not #fail when #run fails more then max_fails'

         it 'should rescue if #final_fail errors' #TODO: and do what? puts to stderr maybe?
      end


   end
end

