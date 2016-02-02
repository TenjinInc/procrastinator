require 'spec_helper'

module Procrastinator
   describe Procrastinator do
      it 'should have a version number' do
         expect(Procrastinator::VERSION).not_to be nil
      end

      # TODO: what if a task is found that doesn't match a defined queue? Do we handle this? Maybe document as their responibility?

      describe '.setup' do
         let(:persister) { double('persister', read_tasks: [], create_task: nil, update_task: nil, delete_task: nil) }
         let(:queues) { {queue1: {prop1: nil, prop2: nil}, queue2: {prop1: nil, prop2: nil}} }

         it 'should return the configured procrastinator environment' do
            env = Procrastinator.setup(persister) do |env|
               queues.each do |name, props|
                  env.define_queue(name, props)
               end
            end

            expect(env).to be_a Environment

            expect(env).to have_attributes(persister: persister, queues: queues)
         end

         it 'should call the provided block and provide the environment' do
            # block = Proc.new do |env|
            #   env.define_queue(:test)
            #end

            expect do |block|
               begin
                Procrastinator.setup(persister, &block)
               rescue RuntimeError
                  # becuase block is stubbed, can't get around this raising
               end
            end.to yield_with_args(instance_of(Environment))
         end

         it 'should require that a block is provided' do
            expect { Procrastinator.setup(persister) }.to raise_error(ArgumentError, 'Procrastinator.setup must be given a block')
         end

         it 'should require at least one queue is defined' do
            expect { Procrastinator.setup(persister) {} }.to raise_error(RuntimeError, 'setup block did not define any queues')
         end

         it 'should call spawn_workers on the environement' do
            expect_any_instance_of(Environment).to receive(:spawn_workers)

            Procrastinator.setup(persister) do |env|
               env.define_queue(:test)
            end
         end
      end
   end
end