require 'spec_helper'

module Procrastinator
   describe Procrastinator do
      it 'should have a version number' do
         expect(Procrastinator::VERSION).not_to be nil
      end

      # TODO: what if a task is found that doesn't match a defined queue? Do we handle this? Maybe document as their responibility?

      describe '.setup' do
         let(:persister) { double('persister', read_tasks: nil, create_task: nil, update_task: nil, delete_task: nil) }
         let(:queues) { {queue1: {prop1: nil, prop2: nil}, queue2: {prop1: nil, prop2: nil}} }

         it 'should return the configured procrastinator environment' do
            env = Procrastinator.setup(persister, queues)

            expect(env).to be_a Environment

            expect(env).to have_attributes(persister: persister, queues: queues)
         end

         it 'should call spawn_workers on the environement' do
            expect_any_instance_of(Environment).to receive(:spawn_workers)

            Procrastinator.setup(persister, queues)
         end
      end
   end
end