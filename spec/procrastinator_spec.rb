# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe Procrastinator do
      it 'should have a version number' do
         expect(Procrastinator::VERSION).not_to be nil
      end

      describe '.setup' do
         include FakeFS::SpecHelpers

         let(:test_task) { Test::Task::AllHooks }
         let(:persister) { Test::Persister.new }

         it 'should provide the block a configuration instance' do
            config = Config.new
            config.load_with(persister)
            config.define_queue(:setup_test_queue, test_task)

            allow(Config).to receive(:new).and_return(config)

            expect do |block|
               Procrastinator.setup(&block)
            end.to yield_with_args(config)
         end

         it 'should return a scheduler configured with config' do
            scheduler = double('scheduler')
            config    = Config.new

            config.load_with(persister)
            config.define_queue(:setup_test_queue, test_task)

            expect(Config).to receive(:new).and_return(config)
            expect(Scheduler).to receive(:new).with(config).and_return(scheduler)

            returned = Procrastinator.setup do |c|
               expect(c).to be config
            end

            expect(returned).to be scheduler
         end

         it 'should require that a block is provided' do
            expect { Procrastinator.setup }.to raise_error(ArgumentError, 'Procrastinator.setup must be given a block')
         end

         it 'should require at least one queue is defined' do
            expect do
               Procrastinator.setup do |config|
                  config.load_with(persister)
               end
            end.to raise_error(SetupError, 'setup block must call #define_queue on the environment')
         end

         it 'should complain if provide_container was called but no queues import container' do
            task_class = Class.new do
               def run
               end
            end

            expect do
               Procrastinator.setup do |config|
                  config.define_queue(:setup_test, task_class)
                  config.load_with(persister)
                  config.provide_container(double('some container'))
               end
            end.to raise_error(SetupError, SetupError::ERR_UNUSED_CONTAINER)
         end

         it 'should NOT complain if provide_container was NOT called and no queues import container' do
            task_class = Class.new do
               def run
               end
            end

            expect do
               Procrastinator.setup do |config|
                  config.define_queue(:setup_test, task_class)
                  config.load_with(persister)
               end
            end.to_not raise_error
         end
      end
   end
end
