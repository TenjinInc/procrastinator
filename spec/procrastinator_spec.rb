require 'spec_helper'

module Procrastinator
   describe Procrastinator do
      it 'should have a version number' do
         expect(Procrastinator::VERSION).not_to be nil
      end

      # TODO: what if a task is found that doesn't match a defined queue? Do we handle this? Maybe document as their responibility?

      describe '.setup' do
         # let(:persister) { double('persister', read_tasks: nil, create_task: nil, update_task: nil, delete_task: nil) }

         it 'should require that the persister not be nil' do
            expect { Procrastinator.setup(nil, email: {}) }.to raise_error(ArgumentError, 'persister cannot be nil')
         end

         it 'should require that the queue definitions not be nil' do
            expect { Procrastinator.setup(double('persister'), nil) }.to raise_error(ArgumentError, 'queue definitions cannot be nil')
         end

         it 'should require that the queue definitions have at least one element' do
            expect { Procrastinator.setup(double('persister'), {}) }.to raise_error(ArgumentError, 'queue definition hash is empty')
         end


         # TODO: Procrastinator.setup(task_repo, email:   {timeout: 1.hour, max_attempts: 15, max_tasks: 5},
         # TODO:                                 cleanup: {timeout: 1.minute, max_attempts: 3, max_tasks: 2} )

         it 'should require the persister respond to #read_tasks' do
            expect do
               Procrastinator.setup(double('persister', create_task: nil, update_task: nil, delete_task: nil), email: {})
            end.to raise_error(MalformedPersisterError, 'persister must repond to #read_tasks')
         end

         it 'should require the persister respond to #create_task' do
            expect do
               Procrastinator.setup(double('persister', read_tasks: nil, update_task: nil, delete_task: nil), email: {})
            end.to raise_error(MalformedPersisterError, 'persister must repond to #create_task')
         end

         it 'should require the persister respond to #update_task' do
            expect do
               Procrastinator.setup(double('persister', read_tasks: nil, create_task: nil, delete_task: nil), email: {})
            end.to raise_error(MalformedPersisterError, 'persister must repond to #update_task')
         end

         it 'should require the persister respond to #delete_task' do
            expect do
               Procrastinator.setup(double('persister', read_tasks: nil, create_task: nil, update_task: nil), email: {})
            end.to raise_error(MalformedPersisterError, 'persister must repond to #delete_task')
         end

         it 'should return the configured procrastinator environment' do
            env = Procrastinator.setup

            expect(env).to be_a Environment

            expect(env).to have_attributes(attr: val)
         end

         # TODO: test for passing in queue name, update period, max_attempts, timeout to queueworker?
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

            # TODO: api: Procrastinator.delay(run_at: Time.now + 10, queue: :email, SendInvitation.new(to: 'bob@example.com'))

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