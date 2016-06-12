require 'spec_helper'

module Procrastinator
   describe Procrastinator do
      around(:each) do |example|
         # need to store and replace this every test as this is a module level variable
         original_mode = Procrastinator.test_mode

         example.run

         Procrastinator.test_mode = original_mode
      end

      it 'should have a version number' do
         expect(Procrastinator::VERSION).not_to be nil
      end

      describe '.setup' do
         let(:persister) { double('persister', read_tasks: [], create_task: nil, update_task: nil, delete_task: nil) }
         let(:queues) { {queue1: {name: nil, max_tasks: nil}, queue2: {name: nil, max_tasks: nil}} }

         it 'should return the configured procrastinator environment' do

            env = Procrastinator.setup(persister) do |env|
               queues.each do |name, props|
                  env.define_queue(name, props)
               end
            end

            expect(env).to be_a Environment

            expect(env).to have_attributes(persister: persister, queue_definitions: queues)
         end

         it 'should call the provided block and provide the environment' do
            expect do |block|
               begin
                  Procrastinator.setup(persister, &block)
               rescue RuntimeError
                  # because block is stubbed, can't get around this raising
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

         it 'should create enable test mode if provided' do
            result = Procrastinator.setup(persister) do |env|
               env.define_queue(:test)
               env.enable_test_mode
            end

            expect(result.test_mode).to be true
         end

         context 'test mode is enabled' do
            before(:each) do
               Procrastinator.test_mode = true
            end

            it 'should create an environment in test mode' do
               result = Procrastinator.setup(persister) do |env|
                  env.define_queue(:test)
               end

               expect(result.test_mode).to be true
            end

            it 'should create every environment in test mode' do
               result1 = Procrastinator.setup(persister) do |env|
                  env.define_queue(:test)
               end
               result2 = Procrastinator.setup(persister) do |env|
                  env.define_queue(:test)
               end

               expect(result1.test_mode).to be true
               expect(result2.test_mode).to be true
            end
         end
      end

      describe '#test_mode=' do
         it 'should assign test mode' do
            Procrastinator.test_mode = true

            expect(Procrastinator.test_mode).to be true
         end
      end
   end
end