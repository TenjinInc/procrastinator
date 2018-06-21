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
         let(:persister) {double('persister', read_tasks: [], create_task: nil, update_task: nil, delete_task: nil)}
         let(:queues) {{queue1: {name: nil, max_tasks: nil, task_class: GoodTask},
                        queue2: {name: nil, max_tasks: nil, task_class: GoodTask}}}

         it 'should return the configured procrastinator environment' do
            FakeFS do # fakefs enabled to cleanly handle default logging
               env = Procrastinator.setup do |env|
                  queues.each do |name, props|
                     env.define_queue(name, GoodTask, props)
                  end

                  env.load_with do
                     persister
                  end
               end

               expect(env).to be_a Environment

               expect(env).to have_attributes(task_loader_instance: persister,
                                              queue_definitions:    queues)
            end
         end

         it 'should call the provided block and provide the environment' do
            expect do |block|
               begin
                  Procrastinator.setup(&block)
               rescue RuntimeError
                  # because block is stubbed, can't get around this raising
               end
            end.to yield_with_args(instance_of(Environment))
         end

         it 'should require that a block is provided' do
            expect {Procrastinator.setup}.to raise_error(ArgumentError, 'Procrastinator.setup must be given a block')
         end

         it 'should require that #load_with is called' do
            expect do
               Procrastinator.setup {}
            end.to raise_error(RuntimeError, 'setup block must call #load_with on the environment')
         end

         it 'should require that #load_with is provided a task loader factory block' do
            err = '#load_with must be given a block that produces a persistence handler for tasks'

            expect do
               Procrastinator.setup {|env| env.load_with}
            end.to raise_error(RuntimeError, err)
         end

         it 'should require at least one queue is defined' do
            expect {Procrastinator.setup do |env|
               env.load_with do
                  double('persister', read_tasks: nil, create_task: nil, update_task: nil, delete_task: nil)
               end
            end}.to raise_error(RuntimeError, 'setup block must call #define_queue on the environment')
         end

         it 'should call spawn_workers on the environment' do
            expect_any_instance_of(Environment).to receive(:spawn_workers)

            Procrastinator.setup do |env|
               env.define_queue(:test, GoodTask)
               env.load_with {persister}
            end
         end

         it 'should enable test mode when declared' do
            result = Procrastinator.setup do |env|
               env.define_queue(:test, GoodTask)
               env.load_with {persister}
               env.enable_test_mode
            end

            expect(result.test_mode).to be true
         end

         context 'test mode is enabled' do
            before(:each) do
               Procrastinator.test_mode = true
            end

            it 'should create an environment in test mode' do
               result = Procrastinator.setup do |env|
                  env.load_with {persister}
                  env.define_queue(:test, GoodTask)
               end

               expect(result.test_mode).to be true
            end

            it 'should create every environment in test mode' do
               result1 = Procrastinator.setup do |env|
                  env.load_with {persister}
                  env.define_queue(:test, GoodTask )
               end
               result2 = Procrastinator.setup do |env|
                  env.load_with {persister}
                  env.define_queue(:test, GoodTask)
               end

               expect(result1.test_mode).to be true
               expect(result2.test_mode).to be true
            end
         end
      end

      describe '#test_mode=' do
         it 'should assign global test mode' do
            Procrastinator.test_mode = true

            expect(Procrastinator.test_mode).to be true
         end
      end
   end
end