# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe Procrastinator::Scheduler do
      let(:test_task) { Test::Task::AllHooks }
      let(:persister) { Test::Persister.new }

      let(:config) do
         Config.new do |c|
            c.with_store(persister) do
               c.define_queue(:emails, test_task)
               c.define_queue(:reminders, test_task)
            end
         end
      end

      let(:scheduler) { Scheduler.new(config) }

      # api: Procrastinator.delay(run_at: Time.now + 10, queue: :email, SendInvitation.new(to: 'bob@example.com'))
      describe '#delay' do
         it 'should record a task on the given queue' do
            [:emails, :reminders].each do |queue_name|
               expect(persister).to receive(:create).with(hash_including(queue: queue_name))

               scheduler.delay(queue_name)
            end
         end

         it 'should record a task with given run_at' do
            run_stamp = '2022-12-25T06:01:00-07:00'

            expect(persister).to receive(:create).with(hash_including(run_at: run_stamp))

            scheduler.delay(:reminders, run_at: run_stamp)
         end

         it 'should record a task with given expire_at' do
            expire_stamp = '2022-12-31T23:59:59-04:00'

            expect(persister).to receive(:create).with(hash_including(expire_at: expire_stamp))

            scheduler.delay(:reminders, expire_at: expire_stamp)
         end

         it 'should complain if they provide NO :data but the task expects it' do
            test_task = Class.new do
               attr_accessor :data, :logger, :container, :scheduler

               def run
               end
            end

            config = Config.new do |c|
               c.define_queue(:data_queue, test_task, store: persister)
            end

            scheduler = Scheduler.new(config)

            err = %[task #{ test_task } expects to receive :data. Provide :data to #delay.]

            expect { scheduler.delay(:data_queue) }.to raise_error(ArgumentError, err)
         end

         it 'should default run_at to now' do
            now = Time.now

            Timecop.freeze(now) do
               expect(persister).to receive(:create).with(hash_including(run_at: now.iso8601))

               scheduler.delay(:reminders)
            end
         end

         it 'should record initial_run_at and run_at to be equal' do
            time = Time.now

            expect(persister).to receive(:create).with(hash_including(run_at:         time.iso8601,
                                                                      initial_run_at: time.iso8601))

            scheduler.delay(:reminders, run_at: time)
         end

         it 'should default expire_at to nil' do
            expect(persister).to receive(:create).with(include(expire_at: nil))

            scheduler.delay(:reminders)
         end

         it 'should NOT complain about well-formed hooks' do
            [:success, :fail, :final_fail].each do |method|
               task = test_task.new

               allow(task).to receive(method)

               expect do
                  scheduler.delay(:reminders)
               end.to_not raise_error
            end
         end

         it 'should complain when the first argument is not a symbol' do
            [5, double('trouble')].each do |arg|
               expect { scheduler.delay(arg) }.to raise_error ArgumentError, <<~ERR
                  must provide a queue name as the first argument. Received: #{ arg }
               ERR
            end
         end
      end

      describe '#reschedule' do
         it 'should create a proxy for the given search parameters' do
            queue      = double('q', to_s: 'q')
            identifier = {id: 4}

            expect(Scheduler::UpdateProxy).to receive(:new).with(config, identifier: hash_including(id:    4,
                                                                                                    queue: queue.to_s))

            scheduler.reschedule(queue, identifier)
         end

         it 'should return the created proxy' do
            proxy = double('proxy')

            allow(Scheduler::UpdateProxy).to receive(:new).and_return(proxy)

            expect(scheduler.reschedule(:test_queue, {})).to be proxy
         end
      end

      describe '#cancel' do
         let(:config) do
            Config.new do |config|
               config.with_store(persister) do
                  config.define_queue(:greeting, test_task)
                  config.define_queue(:reminder, test_task)
               end
            end
         end

         it 'should delete the task matching the given search data' do
            tasks = [{id: 1, queue: :reminder, data: 'user_id: 5'},
                     {id: 2, queue: :reminder, data: 'user_id: 10'}]

            allow(persister).to receive(:read) do |attrs|
               attrs[:data][:user_id] == 5 ? [tasks.first] : [tasks.last]
            end

            # first search
            expect(persister).to receive(:delete).with(2)
            scheduler.cancel(:reminder, data: {user_id: 10})

            # second search
            expect(persister).to receive(:delete).with(1)
            scheduler.cancel(:reminder, data: {user_id: 5})
         end

         it 'should delete the task only on the given queue' do
            tasks = [{id: 1, queue: :reminder, data: 'user_id: 5'},
                     {id: 2, queue: :greeting, data: 'user_id: 5'}]

            allow(persister).to receive(:read) do |attrs|
               attrs[:queue] == :reminder.to_s ? [tasks.first] : [tasks.last]
            end

            # first search
            expect(persister).to receive(:delete).with(2)
            scheduler.cancel(:greeting, data: {user_id: 5})

            # second search
            expect(persister).to receive(:delete).with(1)
            scheduler.cancel(:reminder, data: {user_id: 5})
         end

         it 'should complain if no task matches the given data' do
            allow(persister).to receive(:read).and_return([])

            [{data: {bogus: 6}},
             {data: 'missing data'}].each do |identifier|
               expect(persister).to_not receive(:delete)

               expect do
                  scheduler.cancel(:greeting, identifier)
               end.to raise_error(RuntimeError, "no task matches search: #{ identifier }")
            end
         end

         it 'should complain if multiple task match the given data' do
            allow(persister).to receive(:read).and_return([{id: 1, queue: :reminder, run_at: 0},
                                                           {id: 2, queue: :reminder, run_at: 0}])

            expect(persister).to_not receive(:delete)

            [{run_at: 0},
             {queue: :reminder}].each do |identifier|
               expect do
                  scheduler.cancel(:greeting, identifier)
               end.to raise_error(RuntimeError, "multiple tasks match search: #{ identifier }")
            end
         end
      end

      describe '#work' do
         let(:queue_names) { [:first, :second, :third] }
         let(:config) do
            Config.new do |config|
               queue_names.each { |name| config.define_queue(name, test_task, store: persister) }
            end
         end

         it 'should create a worker for only specified queues' do
            specified = [:first, :third]

            specified.each do |queue|
               expect(QueueWorker).to receive(:new).and_return(double("queue worker #{ queue }", work_one: nil))
            end

            scheduler.work(*specified)
         end

         it 'should create a worker for every queue definition by default' do
            expect(QueueWorker).to receive(:new).exactly(queue_names.length).times

            scheduler.work
         end
      end
   end

   describe Scheduler::UpdateProxy do
      let(:task_id) { double('task id') }
      let(:identifier) { {id: task_id} }
      let(:task) do
         Task.new(TaskMetaData.new(queue: Queue.new(name: :test_queue, task_class: Test::Task::AllHooks), id: task_id),
                  Test::Task::AllHooks.new)
      end
      # need a queue double bc queues are frozen and can't be stubbed
      let(:queue) { double('queue', update: nil, fetch_task: task) }
      let(:update_proxy) { Scheduler::UpdateProxy.new(queue, identifier: identifier) }

      describe '#to' do
         it 'should ask the queue for the task' do
            expect(queue).to receive(:fetch_task).with(identifier)

            update_proxy.to(run_at: Time.now)
         end

         it 'should update the found task' do
            expect(queue).to receive(:update).with(task_id, anything)

            update_proxy.to(run_at: Time.now)
         end

         it 'should update run_at and initial_run_at to the given time' do
            time = '2022-05-01T05:40:00-06:00'

            expect(queue).to receive(:update).with(anything, hash_including(run_at:         time,
                                                                            initial_run_at: time))

            update_proxy.to(run_at: Time.parse(time))
         end

         it 'should reschedule the run_at' do
            expect(task).to receive(:reschedule).with(run_at: 1234)

            update_proxy.to(run_at: 1234)
         end

         it 'should NOT reschedule run_at to nil' do
            expect(task).to_not receive(:reschedule).with(run_at: nil)

            update_proxy.to(run_at: nil, expire_at: 0)
         end

         it 'should reschedule the expire_at' do
            expect(task).to receive(:reschedule).with(expire_at: 4567)

            update_proxy.to(expire_at: 4567)
         end

         it 'should NOT reschedule expire_at to nil' do
            expect(task).to_not receive(:reschedule).with(expire_at: nil)

            update_proxy.to(run_at: 0, expire_at: nil)
         end

         it 'should complain if run_at nor expire_at are provided' do
            expect do
               update_proxy.to
            end.to raise_error(ArgumentError, 'you must provide at least :run_at or :expire_at')
         end

         it 'should not change id, queue, or data' do
            expect(queue).to receive(:update).with(task_id, hash_excluding(:id, :data, :queue))

            update_proxy.to(run_at: Time.now)
         end
      end
   end

   describe Scheduler::SerialWorking do
      let(:test_task) { Test::Task::AllHooks }

      let(:queue_names) { [:first, :second, :third] }

      let(:persister) { Test::Persister.new }
      let(:config) do
         Config.new do |c|
            c.with_store(persister) do
               queue_names.each do |name|
                  c.define_queue(name, test_task)
               end
            end
         end
      end

      # acts on each queue in series.
      # (useful for TDD)
      context '#serially' do
         let(:work_proxy) { Scheduler.new(config).work }
         let(:queue_workers) { work_proxy.workers }

         it 'should call QueueWorker#work_one on each queue worker' do
            queue_workers.each do |worker|
               expect(worker).to receive(:work_one)
            end
            work_proxy.serially
         end

         it 'should call QueueWorker#work_one the specified number of times' do
            queue_workers.each do |worker|
               expect(worker).to receive(:work_one).exactly(2).times
            end

            work_proxy.serially(steps: 2)
         end
      end
   end

   describe Scheduler::ThreadedWorking do
      let(:test_task) { Test::Task::AllHooks }

      let(:queue_names) { [:first, :second, :third] }

      let(:persister) { Test::Persister.new }
      let(:log_level) { false }
      let(:config) do
         Config.new do |c|
            c.with_store(persister) do
               queue_names.each do |name|
                  c.define_queue(name, test_task)
               end
            end
            c.log_with level: log_level
         end
      end

      let(:log_file) { config.log_dir / 'procrastinator.log' }

      before(:each) do
         # prevent actual threading during any testing
         allow(Thread).to receive(:new).and_raise('Must override Thread spawning in test')

         # need to stub fakefs flock because Logger uses it internally and FakeFS does not support it yet
         allow_any_instance_of(FakeFS::File).to receive(:flock)
      end

      # spawns a thread per queue and calls act on each queue worker
      # (useful for same-process one-offs like a manual intervention)
      context '#threaded' do
         let(:thread_double) { double('thread', join: nil, kill: nil, alive?: true, thread_variable_get: nil) }
         let(:scheduler) { Scheduler.new(config) }
         let(:work_proxy) { scheduler.work(*queue_names) }

         let(:log_level) { Logger::FATAL } # silence stdout logger in these tests

         context 'main thread' do
            it 'should spawn a new thread for each specified queue' do
               expect(Thread).to receive(:new).exactly(queue_names.size).times.and_return(thread_double)

               work_proxy.threaded
            end

            it 'should wait for the threads to complete' do
               threads = [double('threadA', join: nil, kill: nil, alive?: true, thread_variable_get: nil),
                          double('threadB', join: nil, kill: nil, alive?: true, thread_variable_get: nil),
                          double('threadC', join: nil, kill: nil, alive?: true, thread_variable_get: nil)]
               allow(Thread).to receive(:new).and_return(*threads)

               threads.each do |thread|
                  expect(thread).to receive(:join).once
               end

               work_proxy.threaded
            end

            it 'should respect the given timeout' do
               allow(Thread).to receive(:new).and_return(thread_double)

               n = 5
               expect(thread_double).to receive(:join).with(n)

               work_proxy.threaded(timeout: n)
            end

            context 'logging enabled' do
               let(:config) do
                  Config.new do |c|
                     queue_names.each do |name|
                        c.define_queue name, Test::Task::AllHooks
                     end
                  end
               end

               it 'should say it is starting threads' do
                  allow(Thread).to receive(:new).and_return(thread_double)

                  msg = 'Starting worker threads...'
                  expect do
                     work_proxy.threaded
                  end.to output(include(msg)).to_stderr

                  expect(log_file).to include_log_line 'INFO', msg
               end
            end
         end

         # ie. testing inside the child thread
         context 'child thread' do
            let(:work_proxy) { Scheduler.new(config).work(:first) }
            let(:worker) { work_proxy.workers.first }

            before(:each) do
               allow(Thread).to receive(:new).and_yield(worker).and_return(thread_double)

               allow(worker).to receive(:work!) # need to stub work because it uses an infiniloop
               allow(worker).to receive(:halt)
            end

            it 'should tell the queue worker to work' do
               expect(worker).to receive(:work!)

               work_proxy.threaded
            end

            # worker#work loops indefinitely, but can be interrupted by shutdown.
            it 'should tell the worker to halt when interrupted' do
               expect(worker).to receive(:halt)

               work_proxy.threaded
            end

            it 'should call halt after work normally' do
               expect(worker).to receive(:halt).once

               work_proxy.threaded
            end

            # gently clean up the other threads when one sibling crashes
            it 'should call halt when errors happen' do
               err = 'dummy test error'
               allow(worker).to receive(:work!).and_raise(StandardError, err)

               expect(worker).to receive(:halt).once

               expect { work_proxy.threaded }.to output.to_stderr # silencing terminal output
            end

            # Be aware that there is also a class-level version of abort_on_exception.
            # This is done per-instance to prevent accidental interactions with other gems, etc
            it 'should set this thread to raise errors to the parent' do
               expect(Thread.current).to receive(:abort_on_exception=).with(true)

               work_proxy.threaded
            end

            context 'log disabled' do
               let(:log_level) { false }

               it 'should log to stderr but not to file' do
                  expect do
                     work_proxy.threaded
                  end.to output.to_stderr

                  expect(log_file).to_not exist
               end
            end

            context 'log enabled' do
               let(:log_level) { Logger::INFO }

               # this is a backstop to the queue worker's internal logging, just in case that fails
               it 'should warn about errors' do
                  msg = 'Crash detected in queue worker thread.'
                  err = 'dummy test error'
                  allow(worker).to receive(:work!).and_raise(StandardError, err)

                  expect do
                     work_proxy.threaded
                  end.to output(include(msg)).to_stderr

                  expect(log_file).to include_log_line 'FATAL', msg
                  expect(log_file.readlines).to include(/\s+#{ err }/) # source error message
                  expect(log_file.readlines).to include(/<module:Procrastinator>/) # and backtrace
               end

               it 'should warn about errors with the crashed queue name' do
                  allow(Thread).to receive(:new).and_return(thread_double)

                  # need this one to be separately tested because the threads group is nil when immediately crashing on #work!
                  err = 'dummy test error'
                  allow(thread_double).to receive(:join).and_raise(StandardError, err)

                  allow(thread_double).to receive(:status).and_return(nil)
                  allow(thread_double).to receive(:thread_variable_get).and_return(worker.name)

                  msg = /Crashed thread: #{ worker.name }/

                  expect do
                     work_proxy.threaded
                  end.to output(msg).to_stderr

                  expect(log_file.readlines).to include(msg) # and backtrace
               end
            end
         end

         context 'SIGINT' do
            it 'should register a SIGINT handler' do
               allow(Thread).to receive(:new).and_return(thread_double)

               expect(Signal).to receive(:trap).with('INT')

               work_proxy.threaded
            end

            it 'should register a SIGINT handler before calling join' do
               allow(Thread).to receive(:new).and_return(thread_double)

               expect(Signal).to receive(:trap).ordered
               expect(thread_double).to receive(:join).ordered

               work_proxy.threaded
            end

            it 'should kill each alive thread in the handler' do
               thread_a = double('threadA', join: nil, kill: nil, alive?: true, thread_variable_get: nil)
               thread_b = double('threadB', join: nil, kill: nil, alive?: false, thread_variable_get: nil)
               thread_c = double('threadC', join: nil, kill: nil, alive?: true, thread_variable_get: nil)
               allow(Thread).to receive(:new).and_return(thread_a, thread_b, thread_c)

               signal_block = nil
               allow(Signal).to receive(:trap) do |&block|
                  signal_block = block
               end

               work_proxy.threaded

               expect(thread_a).to receive(:kill).once
               expect(thread_b).to_not receive(:kill)
               expect(thread_c).to receive(:kill).once
               signal_block&.call
            end

            context 'logging enabled' do
               let(:log_level) { Logger::INFO }

               it 'should say it is shutting down' do
                  thread_a = double('threadA', join: nil, kill: nil, alive?: true, thread_variable_get: nil)
                  allow(Thread).to receive(:new).and_return(thread_a)

                  signal_block = nil
                  allow(Signal).to receive(:trap) do |&block|
                     signal_block = block
                  end

                  msg1 = 'Halting worker threads...'
                  msg2 = 'Threads halted.'

                  expect do
                     work_proxy.threaded
                  end.to output(include(msg1, msg2)).to_stderr

                  signal_block&.call

                  expect(log_file).to include_log_line 'INFO', msg1
                  expect(log_file).to include_log_line 'INFO', msg2
               end
            end
         end
      end
   end

   describe Scheduler::DaemonWorking do
      let(:test_task) { Test::Task::AllHooks }

      let(:queue_names) { [:first, :second, :third] }

      let(:persister) { Test::Persister.new }
      let(:log_level) { Logger::INFO }
      let(:config) do
         Config.new do |c|
            c.with_store(persister) do
               queue_names.each do |name|
                  c.define_queue(name, test_task)
               end
            end
            c.log_with level: log_level
         end
      end

      let(:log_file) { config.log_dir / 'procrastinator.log' }

      before(:each) do
         # prevent actual threading during any testing
         allow(Thread).to receive(:new).and_raise('Must override Thread spawning in test')

         # prevent the global at_exit handlers by default in testing
         allow_any_instance_of(Scheduler).to receive(:at_exit)

         # need to stub fakefs flock because Logger uses it internally and FakeFS does not support it yet
         allow_any_instance_of(FakeFS::File).to receive(:flock)
      end

      # takes over the current process and daemonizes itself.
      # (useful for normal background operations in production)
      context '#daemonized!' do
         let(:work_proxy) { Scheduler.new(config).work(:second) }

         before(:each) do
            # keeping a fallback here; real forks break the rspec runner
            allow(work_proxy).to receive(:fork).and_raise('Testing error: test must stub :fork')
            allow(Dir).to receive(:chdir)
            allow(Process).to receive(:setsid)
         end

         context 'parent process' do
            it 'should exit cleanly' do
               allow(work_proxy).to receive(:fork).and_return(1234)

               expect { work_proxy.daemonized! }.to raise_error(SystemExit) do |error|
                  expect(error.status).to eq(0)
               end
            end

            it 'should clear the session id and exit cleanly again' do
               allow(work_proxy).to receive(:fork).and_return(nil, 5678)

               expect(Process).to receive(:setsid)
               expect { work_proxy.daemonized! }.to raise_error(SystemExit) do |error|
                  expect(error.status).to eq(0)
               end
            end

            it 'should NOT run the given block' do
               allow(work_proxy).to receive(:fork).and_return(1234)

               expect do
                  expect do |block|
                     work_proxy.daemonized!(&block)
                  end.to_not yield_control
               end.to raise_error(SystemExit)
            end
         end
         context 'child process' do
            before(:each) do
               allow(work_proxy).to receive(:fork).and_return(nil)
               allow(Thread).to receive(:new).and_return double('thread double', join: nil, alive?: false)
               allow(work_proxy).to receive(:loop).and_yield
            end

            # prevents pointing to a pwd inherited from a manual terminal run (which might disappear)
            it 'should chdir to root' do
               expect(Dir).to receive(:chdir).with('/')
               work_proxy.daemonized!
            end

            it 'should spawn queues workers in threaded mode' do
               expect(work_proxy).to receive(:threaded)

               work_proxy.daemonized!
            end

            it 'should run the given block' do
               was_run = false
               work_proxy.daemonized! do
                  was_run = true
               end

               expect(was_run).to eq true
            end

            # not sure this is actually necessary to test, so leaving just as a note:
            #    it 'should respond to SIGTERM to exit cleanly'

            context 'process name' do
               let(:max_len) { Scheduler::DaemonWorking::MAX_PROC_LEN }
               let(:max_prog_name) { 'a' * max_len }

               before(:each) do
                  allow(work_proxy).to receive(:system).with('pidof', anything, anything).and_return(false)
               end

               it 'should rename the daemon process' do
                  prog_name = 'vicky'

                  expect(Process).to receive(:setproctitle).with(prog_name)

                  work_proxy.daemonized!(name: prog_name)
               end

               it 'should use a default process name' do
                  expect(Process).to receive(:setproctitle).with(Scheduler::DaemonWorking::PROG_NAME.downcase)

                  work_proxy.daemonized!
               end

               it 'should trim long process names to fit' do
                  maxlen        = Scheduler::DaemonWorking::MAX_PROC_LEN
                  max_proc_name = 'z' * maxlen

                  expect(Process).to receive(:setproctitle).with(max_proc_name)

                  work_proxy.daemonized!(name: "#{ max_proc_name }more")
               end

               it 'should silently ask the system about another process' do
                  prog_name = 'lemming'

                  expect(work_proxy).to receive(:system).with('pidof', prog_name, out: File::NULL)

                  work_proxy.daemonized!(name: prog_name)
               end

               context 'logging enabled' do
                  let(:log_level) { Logger::INFO }

                  it 'should warn if the process name is too long' do
                     name = "#{ max_prog_name }b"

                     msg = "Process name is longer than max length (#{ max_len }). Trimming to fit."

                     expect do
                        work_proxy.daemonized!(name: name)
                     end.to_not output.to_stderr

                     expect(log_file).to include_log_line 'WARN', msg
                  end

                  it 'should log warning when an existing process has the same name' do
                     prog_name = 'lemming'

                     allow(work_proxy).to receive(:system).with('pidof', prog_name, anything).and_return(true)

                     msg = "Another process is already named '#{ prog_name }'. Consider the 'name:' keyword to distinguish."

                     expect do
                        work_proxy.daemonized!(name: prog_name)
                     end.to_not output.to_stderr

                     expect(log_file).to include_log_line 'WARN', msg
                  end
               end
            end

            context 'pid file' do
               let(:pid_file) { Pathname.new 'pids/procrastinator.pid' }

               it 'should create pid file at the provided filename' do
                  pid_file = Pathname.new('/tmp/atomic-coffee/beans.pid')
                  work_proxy.daemonized!(pid_path: pid_file)

                  expect(pid_file).to exist
                  expect(pid_file).to be_file
               end

               it 'should use the provided pid directory' do
                  pid_dir = Pathname.new('/tmp/atomic-coffee')
                  work_proxy.daemonized!(pid_path: pid_dir)

                  expect(pid_dir).to exist
                  expect(pid_dir).to be_directory
                  expect(pid_dir / Scheduler::DaemonWorking::DEFAULT_PID_FILE).to exist
               end

               it 'should use a default pid dir' do
                  # wrap in new pathname to translate into FakeFS
                  pid_path = Pathname.new(Scheduler::DaemonWorking::DEFAULT_PID_DIR) / Scheduler::DaemonWorking::DEFAULT_PID_FILE
                  work_proxy.daemonized!
                  expect(pid_path).to exist
               end

               it 'should convert the path to absolute' do
                  pid_path = Pathname.new('./up/../pid/something.pid')
                  work_proxy.daemonized!(pid_path: pid_path)
                  expect(pid_path.expand_path).to exist
               end

               it 'should write its pid file' do
                  pid = 12345
                  allow(Process).to receive(:pid).and_return(pid)
                  work_proxy.daemonized!(pid_path: pid_file)

                  file_content = File.read(pid_file)
                  expect(file_content).to eq(pid.to_s)
               end

               it 'should clean up the pid file on exit' do
                  # stub out at_exit to force it to run immediately
                  expect(work_proxy).to receive(:at_exit).and_yield

                  work_proxy.daemonized!

                  expect(pid_file).to_not exist
               end

               it 'should be okay with the pid file not existing' do
                  # stub out at_exit to force it to run immediately
                  expect(work_proxy).to receive(:at_exit) do |&block|
                     pid_file.delete
                     block.call
                  end

                  work_proxy.daemonized!(pid_path: pid_file)
               end

               context 'process already exists' do
                  before(:each) do
                     pid_file.dirname.mkpath
                     pid_file.write(1234)
                     allow(Process).to receive(:getpgid).and_raise Errno::ESRCH, 'No such process'
                  end

                  it 'should log warning about removing old pid file' do
                     msg = "Replacing old pid file of defunct process (pid 1234) at #{ pid_file.expand_path }."

                     work_proxy.daemonized!(pid_path: pid_file)

                     expect(log_file).to include_log_line 'WARN', msg
                  end
               end

               context 'process already exists' do
                  before(:each) do
                     pid_file.dirname.mkpath
                     pid_file.write(1234)
                     allow(Process).to receive(:getpgid).and_return 5678
                  end

                  it 'should ask about the process in the pid file' do
                     expect(Process).to receive(:getpgid).with(1234)

                     expect do
                        work_proxy.daemonized!(pid_path: pid_file)
                     end.to raise_error ProcessExistsError
                  end

                  it 'should error out' do
                     expect do
                        work_proxy.daemonized!(pid_path: pid_file)
                     end.to raise_error ProcessExistsError
                  end

                  it 'should log the process collision' do
                     hint = 'Either terminate that process or remove the pid file.'
                     msg  = "Another process already already exists for #{ pid_file.expand_path } (pid 1234). #{ hint }"

                     expect do
                        work_proxy.daemonized!(pid_path: pid_file)
                     end.to raise_error ProcessExistsError, msg

                     expect(log_file).to include_log_line 'FATAL', msg
                  end
               end
            end

            context 'status output' do
               let(:log_level) { Logger::INFO }

               it 'should open a log file' do
                  allow(Process).to receive(:pid).and_return(12345)
                  log_path = config.log_dir / 'procrastinator.log'

                  msg = 12345.to_s

                  expect do
                     work_proxy.daemonized!
                  end.to_not output.to_stderr

                  expect(log_path).to exist
                  expect(log_file).to include_log_line 'procrastinator', msg
               end

               it 'should print starting the daemon' do
                  msg = 'Starting Procrastinator daemon...'

                  expect do
                     work_proxy.daemonized!
                  end.to_not output.to_stderr

                  expect(log_file).to include_log_line 'INFO', msg
               end

               it 'should print the daemon pid' do
                  allow(Process).to receive(:pid).and_return(1234)

                  msg1 = 'Procrastinator running. Process ID: 1234'

                  expect do
                     work_proxy.daemonized!
                  end.to_not output.to_stderr

                  expect(log_file).to include_log_line 'INFO', msg1
               end

               it 'should print a clean exit' do
                  allow(Process).to receive(:pid).and_return(1234)

                  # stub out at_exit to force it to run immediately
                  expect(work_proxy).to receive(:at_exit).and_yield

                  msg = 'Procrastinator (pid 1234) halted.'

                  expect do
                     work_proxy.daemonized!
                  end.to_not output.to_stderr

                  expect(log_file).to include_log_line 'INFO', msg
               end

               context 'logging disabled' do
                  let(:log_level) { false }

                  it 'should create a null logger' do
                     expect do
                        work_proxy.daemonized!
                     end.to_not output.to_stderr

                     expect(log_file).to_not exist
                  end
               end
            end
         end
      end
   end
end
