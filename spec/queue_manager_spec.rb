# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe QueueManager do
      let(:test_task) { Test::Task::AllHooks }

      describe '#spawn_workers' do
         include FakeFS::SpecHelpers

         let(:persister) { Test::Persister.new }
         let(:config) do
            config = Config.new
            config.load_with(persister)
            config
         end

         let(:manager) { QueueManager.new(config) }

         before(:each) do
            FakeFS.clear! if FakeFS.activated?
         end

         context 'main thread' do
            before(:each) do
               allow(Thread).to receive(:new)
            end

            it 'should start a worker thread for each queue' do
               n = 5

               n.times do |i|
                  config.define_queue("queue#{ i }", test_task)
               end

               expect(Thread).to receive(:new).exactly(n).times

               manager.spawn_workers
            end

            it 'should create a worker for each queue definition' do
               queue_defs = [:test2a, :test2b, :test2c]
               queue_defs.each do |name|
                  config.define_queue(name, test_task)
               end

               expect(QueueWorker).to receive(:new).with(hash_including(queue: config.queues[0]))
               expect(QueueWorker).to receive(:new).with(hash_including(queue: config.queues[1]))
               expect(QueueWorker).to receive(:new).with(hash_including(queue: config.queues[2]))

               manager.spawn_workers
            end

            it 'should pass config to the workers' do
               config.define_queue(:test_queue, test_task)

               expect(QueueWorker).to receive(:new)
                                            .with(hash_including(config: config))
                                            .and_return(double('worker'))
               manager.spawn_workers
            end

            it 'should pass scheduler to the workers' do
               config.define_queue(:test_queue, test_task)

               expect(QueueWorker).to receive(:new)
                                            .with(hash_including(:scheduler))
                                            .and_return(double('worker'))
               manager.spawn_workers
            end

            # TODO: use this if threads end up being useful to store refs to
            # it 'should store the worker threads in the manager' do
            #    worker = double('queue worker 3', long_name: 'work3')
            #
            #    thr = double('some thread')
            #
            #    config.define_queue(:test_queue, test_task)
            #
            #    allow(Thread).to receive(:new).and_return(thr)
            #
            #    manager.spawn_workers
            #
            #    expect(manager.workers).to eq(worker => thr)
            # end
         end

         context 'worker thread' do
            include FakeFS::SpecHelpers

            before(:each) do
               allow(Thread).to receive(:new).and_yield

               allow_any_instance_of(QueueWorker).to receive(:work)

               allow_any_instance_of(QueueManager).to receive(:shutdown_worker)
            end

            it 'should tell the worker process to work' do
               config.define_queue(:test_queue, test_task)

               worker = double('worker')

               allow(QueueWorker).to receive(:new).and_return(worker)

               expect(worker).to receive(:work)

               manager.spawn_workers
            end
         end
      end

      describe '#act' do
         include FakeFS::SpecHelpers

         let(:persister) { double('persister', read: [], create: nil, update: nil, delete: nil) }

         let(:config) do
            config = Config.new
            config.load_with(persister)
            config.define_queue(:test1, test_task)
            config.define_queue(:test2, test_task)
            config.define_queue(:test3, test_task)
            config
         end

         let(:manager) { QueueManager.new(config) }

         before(:each) do
            allow(Thread).to receive(:new)
            manager.spawn_workers
         end

         it 'should call QueueWorker#act on every queue worker' do
            expect(manager.workers.size).to eq 3

            manager.workers.each do |worker|
               expect(worker).to receive(:act)
            end

            manager.act
         end

         it 'should call QueueWorker#act on queue worker for given queues only' do
            workers = manager.workers

            worker1 = workers.find { |w| w.name == :test1 }
            worker2 = workers.find { |w| w.name == :test2 }
            worker3 = workers.find { |w| w.name == :test3 }

            expect(worker1).to_not receive(:act)
            expect(worker2).to receive(:act)
            expect(worker3).to receive(:act)

            manager.act(:test2, :test3)
         end
      end
   end
end
