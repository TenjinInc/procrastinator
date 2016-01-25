require 'spec_helper'

describe Procrastinator::Task do
   it 'should #run when the time is passed' do

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

   it 'should complain when no queue is given' # tODO: maybe there is a default :main queue?
   it 'should complain when no run_at is given' # TODO: or default to now? it's not wrong, becuase you may just want it on a separate thread
end
