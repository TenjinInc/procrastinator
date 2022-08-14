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
               expect(QueueWorker).to receive(:new).and_return(double("queue worker #{ queue }", work_one: nil))
            end

            manager.work(*specified)
         end

         it 'should create a worker for every queue definition by default' do
            queue_names.each do |name|
               config.define_queue(name, test_task)
            end

            queue_names.each do |queue|
               expect(QueueWorker).to receive(:new).and_return(double("queue worker #{ queue }", work_one: nil))
            end

            manager.work
         end

      end

      context 'QueueWorkerProxy' do
         # acts on each queue in series.
         # (useful for TDD)
         context '#serially' do
            it 'should call QueueWorker#act on only specified queue workers' do
               queue_names.each do |name|
                  config.define_queue(name, test_task)
               end

               workers = queue_names.collect do |queue_name|
                  double("queue worker #{ queue_name }")
               end

               allow(QueueWorker).to receive(:new).and_return(workers[1], workers[2])

               expect(workers[0]).to_not receive(:work_one)
               expect(workers[1]).to receive(:work_one)
               expect(workers[2]).to receive(:work_one)

               manager.work(:second, :third).serially
            end

            it 'should call QueueWorker#act on every queue worker by default' do
               queue_names.each do |name|
                  config.define_queue(name, test_task)
               end

               workers = queue_names.collect do |queue_name|
                  worker = double("queue worker #{ queue_name }")
                  expect(worker).to receive(:work_one)
                  worker
               end

               allow(QueueWorker).to receive(:new).and_return(*workers)

               manager.work.serially
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
                  expect(worker).to receive(:work_one).exactly(2).times
               end

               manager.work.serially(steps: 2)
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
         context '#daemonized!' do
            let(:worker_proxy) { manager.work }

            before(:each) do
               FakeFS.activate!
               # keeping a fallback here; real forks break the rspec runner
               allow(worker_proxy).to receive(:fork).and_raise('Testing error: test must stub :fork')
               allow(Dir).to receive(:chdir)
               allow(Process).to receive(:setsid)
            end

            context 'parent process' do
               it 'should exit cleanly' do
                  allow(worker_proxy).to receive(:fork).and_return(1234)

                  expect { worker_proxy.daemonized! }.to raise_error(SystemExit) do |error|
                     expect(error.status).to eq(0)
                  end
               end

               it 'should clear the session id and exit cleanly again' do
                  allow(worker_proxy).to receive(:fork).and_return(nil, 5678)

                  expect(Process).to receive(:setsid)
                  expect { worker_proxy.daemonized! }.to raise_error(SystemExit) do |error|
                     expect(error.status).to eq(0)
                  end
               end
            end
            context 'child process' do
               before(:each) do
                  allow(worker_proxy).to receive(:fork).and_return(nil)
                  allow(worker_proxy).to receive(:threaded)
                  allow(worker_proxy).to receive(:loop).and_yield
               end

               # prevents pointing to a pwd inherited from a manual terminal run
               it 'should chdir to root' do
                  expect(Dir).to receive(:chdir).with('/')
                  worker_proxy.daemonized!
               end

               it 'should spawn queues workers in threaded mode' do
                  expect(worker_proxy).to receive(:threaded)

                  worker_proxy.daemonized!
               end

               # not sure this is actually necessary to test, so leaving just as a note:
               #    it 'should respond to SIGTERM to exit cleanly'

               context 'process name' do
                  it 'should rename the daemon process' do
                     procname = 'deemins'

                     expect(Process).to receive(:setproctitle).with(procname)

                     worker_proxy.daemonized!(name: procname)
                  end

                  it 'should warn if the process name is too long' do
                     maxlen       = Procrastinator::QueueManager::QueueWorkerProxy::MAX_PROC_LEN
                     max_procname = 'a' * maxlen

                     msg = /^Warning: process name is longer than max length \(#{ maxlen }\). Trimming to fit.$/

                     expect { worker_proxy.daemonized!(name: max_procname + 'b') }.to output(msg).to_stderr
                  end

                  it 'should warn trim long process names to fit' do
                     maxlen       = Procrastinator::QueueManager::QueueWorkerProxy::MAX_PROC_LEN
                     max_procname = 'z' * maxlen

                     expect(Process).to receive(:setproctitle).with(max_procname)

                     worker_proxy.daemonized!(name: max_procname + 'more')
                  end

                  it 'should warn when an existing process has the same name' do
                     procname = 'lemming'

                     msg = /^Warning: a process is already named "#{ procname }". Consider the "name:" argument to distinguish.$/

                     expect { worker_proxy.daemonized!(name: procname) }.to output(msg).to_stderr

                     worker_proxy.daemonized!(name: procname)
                  end
               end

               context 'pid file' do
                  let(:pid_file) { Pathname.new 'pids/procrastinator.pid' }

                  it 'should create pid file at the provided filename' do
                     pid_file = Pathname.new('/tmp/atomic-coffee/beans.pid')
                     worker_proxy.daemonized!(pid_path: pid_file)

                     expect(pid_file).to exist
                     expect(pid_file).to be_file
                  end

                  it 'should use the provided pid directory' do
                     pid_dir = Pathname.new('/tmp/atomic-coffee')
                     worker_proxy.daemonized!(pid_path: pid_dir)

                     expect(pid_dir).to exist
                     expect(pid_dir).to be_directory
                     expect(pid_dir / QueueManager::QueueWorkerProxy::DEFAULT_PID_FILE).to exist
                  end

                  it 'should use a default pid dir' do
                     worker_proxy.daemonized!
                     pid_path = QueueManager::QueueWorkerProxy::DEFAULT_PID_DIR / QueueManager::QueueWorkerProxy::DEFAULT_PID_FILE
                     expect(pid_path).to exist
                  end

                  it 'should write its pid file' do
                     pid = 12345
                     allow(Process).to receive(:pid).and_return(pid)
                     worker_proxy.daemonized!(pid_path: pid_file)

                     file_content = File.read(pid_file)
                     expect(file_content).to eq(pid.to_s)
                  end

                  it 'should clean up the pid file on exit' do
                     # stub out at_exit to force it to run immediately
                     expect(worker_proxy).to receive(:at_exit).and_yield

                     worker_proxy.daemonized!

                     expect(pid_file).to_not exist
                  end

                  it 'should be okay with the pid file not existing' do
                     # stub out at_exit to force it to run immediately
                     expect(worker_proxy).to receive(:at_exit) do |&block|
                        pid_file.delete
                        block.call
                     end

                     worker_proxy.daemonized!(pid_path: pid_file)
                  end
               end

               context 'status output' do
                  it 'should print starting the daemon' do
                     expect { worker_proxy.daemonized! }.to output(/^Starting Procrastinator...$/).to_stderr
                  end

                  it 'should print the daemon pid' do
                     [1234, 5678].each do |pid|
                        allow(Process).to receive(:pid).and_return(pid)

                        expect { worker_proxy.daemonized! }.to output(/^Procrastinator running. Process ID: #{ pid }$/).to_stderr
                     end
                  end

                  it 'should print a clean exit' do
                     [1234, 5678].each do |pid|
                        allow(Process).to receive(:pid).and_return(pid)

                        # stub out at_exit to force it to run immediately
                        expect(worker_proxy).to receive(:at_exit).and_yield

                        expect { worker_proxy.daemonized! }.to output(/^Procrastinator \(pid #{ pid }\) halted.$/).to_stderr
                     end
                  end
               end
            end
         end
      end
   end
end
