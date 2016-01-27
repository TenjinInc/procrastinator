require 'spec_helper'

describe Procrastinator do
   it 'should have a version number' do
      expect(Procrastinator::VERSION).not_to be nil
   end

   # Procrastinator.setup do
   #    define_queue(:invite_email, max_fails: 6, timeout: 1500)
   #    define_queue(:reminder_email, max_fails: 3, timeout: 1000)
   #    define_queue(:cleanup, max_fails: 2, timeout: 500)
   #
   #    # calls CRUD methods in expected interface on the given persister
   #    task_io(@persister)
   # end
   #
   # Procrastinator.delay(run_at: Time.now + 10, queue: :email, SendInvitation.new(to: 'bob@example.com'))

   # TODO: what if a task has no queue? this is something the #go method will need to handle


   describe '.setup' do
      it 'should require a queue-reading block' # ie how to read the queue table
      it 'should require a queue-writing block' # TODO keep?

      it 'should require a task-reading block' # ie how to read the task table
      it 'should require a task-writing block' # TODO keep?
   end

   describe '.delay' do
      it 'should record a task'

      it 'should complain when the given queue is not registered'
   end

   describe '.spawn_worker' do
      it 'should fork a worker process for the given queue' # tODO: test that it forks a process, and names it
      it 'should tell the worker process to work' # TODO and that the subprocess creates a worker and #works
      it 'should kill children on natural exit'
      it 'should kill children on receiving a termination signal' #TODO: SIGKILL, SIGTERM, SIGQUIT, SIGINT
      # TODO: test for any zombie processes

      after(:each) do
         # tODO: how do we figure out how to find which ones are written by the tests?
         # tODO: kill any zombie processes left by the tests
      end
   end

   describe '#work' do
      it 'should run standalone'
   end
end

