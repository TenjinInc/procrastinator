require 'spec_helper'

module Procrastinator
   describe Procrastinator do
      it 'should have a version number' do
         expect(Procrastinator::VERSION).not_to be nil
      end

      # TODO: Procrastinator.new(queues: hash_of_queue_defs, persister: persister)
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

      # TODO: what if a task is found that doesn't match a defined queue? this is something the #go method will need to handle

      describe '.setup' do
         it 'should require a persistence strategy be given'
         it 'should require queue definitions be given'

         # TODO: test for pasisng in queue name, update period, max_attempts, timeout to queueworker?

         it 'should require the persister respond to #read_tasks' # TODO: MalformedPersisterError
         it 'should require the persister respond to #create_task' # TODO: MalformedPersisterError
         it 'should require the persister respond to #update_task' # TODO: MalformedPersisterError
         it 'should require the persister respond to #delete_task' # TODO: MalformedPersisterError

         it 'should return the configured procrastinator'

         it 'should fork a worker process for each queue' # tODO: test that it forks a process, and names it
         it 'should tell the worker process to work' # TODO and that the subprocess creates a worker and #works
         it 'should kill children on natural exit'
         it 'should kill children on receiving a termination signal' #TODO: SIGKILL, SIGTERM, SIGQUIT, SIGINT

         # TODO: test for any zombie processes

         after(:each) do
            # tODO: how do we figure out how to find which ones are spawned by the tests?
            # tODO: kill any zombie processes left by the tests
         end
      end

      describe Environment do
         describe '#delay' do
            let(:procrastinator) { instance_double(Environment) }

            it 'should record a task'

            it 'should complain when the given queue is not registered'

            it 'should record initial_run_at and run_at to be the same'

            it 'should require queue be provided if there is more than one queue defined'

            it 'should not require queue be provided if there only one queue defined'

            it 'should require id, task be provided'

            it 'should require id, task not be nil'

            it 'should default expire_at, timeout, max_attempts to nil'

            it 'should default run_at to now' #do
            #    now = Time.now
            #    stub_yaml(task)
            #
            #    Timecop.freeze(now) do
            #       worker = TaskWorker.new(task: nil)
            #
            #       expect(worker.run_at).to eq now
            #    end
            # end
         end
      end
   end
end