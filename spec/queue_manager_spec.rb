# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe QueueManager do
      let(:test_task) { Test::Task::AllHooks }

      let(:thread_double) { double('thread', join: nil) }

      before(:each) do
         FakeFS.clear! if FakeFS.activated?

         # prevent actual threading during any testing
         allow(Thread).to receive(:new).and_return(thread_double)
      end

      let(:queue_names) { [:first, :second, :third] }

      let(:persister) { Test::Persister.new }
      let(:config) do
         config = Config.new
         config.load_with(persister)
         config
      end

      let(:manager) { QueueManager.new(config) }

      describe '#work' do
         it 'should create a worker for only specified queues' do
            queue_names.each do |name|
               config.define_queue(name, test_task)
            end

            specified = [:first, :third]

            specified.each do |queue|
               expect(QueueWorker).to receive(:new).and_return(double("queue worker #{ queue }", act: nil))
            end

            manager.work(*specified)
         end

         it 'should create a worker for every queue definition by default' do
            queue_names.each do |name|
               config.define_queue(name, test_task)
            end

            queue_names.each do |queue|
               expect(QueueWorker).to receive(:new).and_return(double("queue worker #{ queue }", act: nil))
            end

            manager.work
         end

      end

      context 'QueueWorkerProxy' do
         # acts on each queue in series.
         # (useful for TDD)
         context '#stepwise' do
            it 'should call QueueWorker#act on only specified queue workers' do
               queue_names.each do |name|
                  config.define_queue(name, test_task)
               end

               workers = queue_names.collect do |queue_name|
                  double("queue worker #{ queue_name }")
               end

               allow(QueueWorker).to receive(:new).and_return(workers[1], workers[2])

               expect(workers[0]).to_not receive(:act)
               expect(workers[1]).to receive(:act)
               expect(workers[2]).to receive(:act)

               manager.work(:second, :third).stepwise
            end

            it 'should call QueueWorker#act on every queue worker by default' do
               queue_names.each do |name|
                  config.define_queue(name, test_task)
               end

               workers = queue_names.collect do |queue_name|
                  worker = double("queue worker #{ queue_name }")
                  expect(worker).to receive(:act)
                  worker
               end

               allow(QueueWorker).to receive(:new).and_return(*workers)

               manager.work.stepwise
            end

            it 'should call QueueWorker#act the specified number of times' do
               queue_names.each do |name|
                  config.define_queue(name, test_task)
               end

               workers = queue_names.collect do |queue_name|
                  double("queue worker #{ queue_name }")
               end

               allow(QueueWorker).to receive(:new).and_return(*workers)

               workers.each do |worker|
                  expect(worker).to receive(:act).exactly(2).times
               end

               manager.work.stepwise(2)
            end
         end

         # spawns a thread per queue and calls act on each queue worker
         # (useful for same-process one-offs like a manual intervention)
         context '#threaded' do
            it 'should spawn a new thread for each specified queue' do
               queue_names.each do |name|
                  config.define_queue(name, test_task)
               end

               [queue_names, [:second, :third]].each do |queues|
                  expect(Thread).to receive(:new).exactly(queues.size).times

                  manager.work(*queues).threaded
               end
            end

            # ie. testing inside the child thread
            it 'should tell the queue worker to work on the thread' do
               allow(Thread).to receive(:new).and_yield.and_return(thread_double)

               config.define_queue(:test_queue, test_task)

               worker = double('worker')

               allow(QueueWorker).to receive(:new).and_return(worker)

               expect(worker).to receive(:work)

               manager.work.threaded
            end

            it 'should wait for the threads to complete' do
               config.define_queue(:first, test_task)
               config.define_queue(:second, test_task)

               expect(thread_double).to receive(:join).exactly(2).times

               manager.work.threaded
            end

            it 'should wait respect the given timeout' do
               config.define_queue(:test_queue, test_task)

               n = 5
               expect(thread_double).to receive(:join).with(n)

               manager.work.threaded(timeout: n)
            end
         end

         # takes over the current process and daemonizes itself.
         # (useful for normal background operations in production)
         context '#daemonize' do
            pending 'this'
         end
      end
   end
end
