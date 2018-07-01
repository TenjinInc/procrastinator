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
         let(:test_task) {Test::Task::AllHooks}
         let(:persister) {double('persister', read_tasks: [], create_task: nil, update_task: nil, delete_task: nil)}

         it 'should return a procrastinator environment configured via the block' do
            env_double    = double('env')
            config_double = double('config')

            allow(env_double).to receive(:spawn_workers)
            allow(config_double).to receive(:verify)

            expect(Config).to receive(:new).and_return(config_double)
            expect(QueueManager).to receive(:new).with(config_double).and_return(env_double)

            returned_env = Procrastinator.setup do |config|
               expect(config).to be config_double
            end

            expect(returned_env).to be env_double
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
               Procrastinator.setup {|config| config.load_with}
            end.to raise_error(RuntimeError, err)
         end

         it 'should require at least one queue is defined' do
            expect {Procrastinator.setup do |config|
               config.load_with {}
            end}.to raise_error(RuntimeError, 'setup block must call #define_queue on the environment')
         end

         it 'should complain if provide_context was called but no queues import context' do
            task_class = Class.new do
               def run
               end
            end

            err = <<~ERROR
               setup block called #provide_context, but no queue task classes import :context.

               Add this to Task classes that expect to receive the context:

                  include Procrastinator::Task

                  import_task_data(:context)
            ERROR

            expect {Procrastinator.setup do |config|
               config.define_queue(:test, task_class)
               config.load_with {persister}
               config.provide_context {double('some context')}
            end}.to raise_error(RuntimeError, err)
         end

         it 'should NOT complain if provide_context was NOT called and no queues import context' do
            task_class = Class.new do
               def run
               end
            end

            expect {Procrastinator.setup do |config|
               config.define_queue(:test, task_class)
               config.load_with {persister}
            end}.to_not raise_error
         end

         it 'should call spawn_workers on the environment' do
            expect_any_instance_of(QueueManager).to receive(:spawn_workers)

            Procrastinator.setup do |config|
               config.define_queue(:test, test_task)
               config.load_with {persister}
            end
         end

         context 'test mode is enabled globally' do
            before(:each) do
               Procrastinator.test_mode = true
            end

            it 'should create an environment in test mode' do
               built_config = nil

               Procrastinator.setup do |config|
                  built_config = config

                  config.load_with {persister}
                  config.define_queue(:test, test_task)
               end

               expect(built_config.test_mode?).to be true
            end

            it 'should create every subsequent environment in test mode' do
               config_1 = nil
               config_2 = nil

               Procrastinator.setup do |config|
                  config_1 = config

                  config.load_with {persister}
                  config.define_queue(:test, test_task)
               end
               Procrastinator.setup do |config|
                  config_2 = config

                  config.load_with {persister}
                  config.define_queue(:test, test_task)
               end

               expect(config_1.test_mode?).to be true
               expect(config_2.test_mode?).to be true
            end
         end

         context 'test mode is disabled globally' do
            before(:each) do
               Procrastinator.test_mode = false
            end

            it 'should create a normal environment' do
               built_config = nil

               Procrastinator.setup do |config|
                  built_config = config

                  config.load_with {persister}
                  config.define_queue(:test, test_task)
               end

               expect(built_config.test_mode?).to be false
            end

            it 'should create every environment without test mode' do
               config_1 = nil
               config_2 = nil

               Procrastinator.setup do |config|
                  config_1 = config

                  config.load_with {persister}
                  config.define_queue(:test, test_task)
               end
               Procrastinator.setup do |config|
                  config_2 = config

                  config.load_with {persister}
                  config.define_queue(:test, test_task)
               end

               expect(config_1.test_mode?).to be false
               expect(config_2.test_mode?).to be false
            end

            it 'should override the global if enabled in the environment' do
               config_1 = nil
               config_2 = nil

               Procrastinator.setup do |config|
                  config_1 = config

                  config.enable_test_mode
                  config.load_with {persister}
                  config.define_queue(:test, test_task)
               end
               Procrastinator.setup do |config|
                  config_2 = config

                  config.load_with {persister}
                  config.define_queue(:test, test_task)
               end

               expect(config_1.test_mode?).to be true
               expect(config_2.test_mode?).to be false
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