require 'spec_helper'

describe Procrastinator::Task do
   it 'should default run_at to now' do
      now = Time.now

      Timecop.freeze(now) do
         task = Procrastinator::Task.new(queue: :test_queue)

         expect(task.run_at).to == now
      end
   end

   it 'should complain when no queue is given' # tODO: maybe there is a default :main queue?
   it 'should complain when the given queue is not registered' # tODO: maybe there is a default :main queue?
end
