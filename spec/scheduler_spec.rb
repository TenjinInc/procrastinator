# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe Procrastinator::Scheduler do
      let(:persister) { Test::Persister.new }

      let(:config) do
         Config.new do |c|
            c.with_store(persister) do
               c.define_queue(:emails, Test::MockTask)
               c.define_queue(:reminders, Test::MockTask)
            end
         end
      end

      let(:scheduler) { Scheduler.new(config) }

      describe '#delay' do
         before do
            allow(persister).to receive(:create)
         end

         it 'should record a task on the given queue' do
            [:emails, :reminders].each do |queue_name|
               scheduler.defer(queue_name)

               expect(persister).to have_received(:create).with(hash_including(queue: queue_name.to_s))
            end
         end

         it 'should record a task with given run_at' do
            run_stamp = '2022-12-25T06:01:00-07:00'

            scheduler.defer(:reminders, run_at: run_stamp)

            expect(persister).to have_received(:create).with(hash_including(run_at: Time.parse(run_stamp)))
         end

         it 'should record a task with given expire_at' do
            expire_stamp = '2022-12-31T23:59:59-04:00'

            scheduler.defer(:reminders, expire_at: expire_stamp)

            expect(persister).to have_received(:create).with(hash_including(expire_at: Time.parse(expire_stamp)))
         end

         it 'should complain if they provide NO :data but the task expects it' do
            test_task = Test::MockTaskWithData

            config = Config.new do |c|
               c.define_queue(:data_queue, test_task, store: persister)
            end

            scheduler = Scheduler.new(config)

            err = %[task #{ test_task } expects to receive :data. Provide :data to #delay.]

            expect { scheduler.defer(:data_queue) }.to raise_error(ArgumentError, err)
         end

         it 'should default run_at to now' do
            now = Time.now

            Timecop.freeze(now) do
               scheduler.defer(:reminders)

               expect(persister).to have_received(:create).with(hash_including(run_at: now))
            end
         end

         it 'should record initial_run_at and run_at to be equal' do
            time = Time.now

            scheduler.defer(:reminders, run_at: time)

            expect(persister).to have_received(:create).with(hash_including(run_at:         time,
                                                                            initial_run_at: time))
         end

         it 'should default expire_at to nil' do
            scheduler.defer(:reminders)

            expect(persister).to have_received(:create).with(include(expire_at: nil))
         end

         it 'should NOT complain about well-formed hooks' do
            [:success, :fail, :final_fail].each do |method|
               task = Test::MockTask.new

               allow(task).to receive(method)

               expect do
                  scheduler.defer(:reminders)
               end.to_not raise_error
            end
         end

         it 'should complain when the first argument is not a symbol' do
            [5, double('trouble')].each do |arg|
               expect { scheduler.defer(arg) }.to raise_error ArgumentError, <<~ERR
                  must provide a queue name as the first argument. Received: #{ arg }
               ERR
            end
         end
      end

      describe '#reschedule' do
         it 'should create a proxy for chaining' do
            proxy = scheduler.reschedule(:reminders, {id: 4})

            expect(proxy).to be_a Scheduler::UpdateProxy
         end

         it 'should create a proxy for the given queue' do
            allow(Scheduler::UpdateProxy).to receive(:new).and_call_original

            scheduler.reschedule(:reminders, id: 12358)

            expect(Scheduler::UpdateProxy).to have_received(:new).with(config.queue(name: :reminders), anything)
         end

         it 'should create a proxy for the given search parameters' do
            identifier = {some: 'identifier', data: 'chidi@example.com'}

            allow(Scheduler::UpdateProxy).to receive(:new).and_call_original

            scheduler.reschedule(:reminders, identifier)

            expect(Scheduler::UpdateProxy).to have_received(:new).with(anything, identifier: identifier)
         end

         it 'should return the created proxy' do
            proxy = double('proxy')

            allow(Scheduler::UpdateProxy).to receive(:new).and_return(proxy)

            expect(scheduler.reschedule(:emails, {})).to be proxy
         end
      end

      describe '#cancel' do
         let(:config) do
            Config.new do |config|
               config.with_store(persister) do
                  config.define_queue(:greeting, Test::MockTask)
                  config.define_queue(:reminder, Test::MockTask)
               end
            end
         end

         it 'should delete the task matching the given search data' do
            tasks = [
                  {id: 1, queue: :reminder, data: '{"user_id": 5}'},
                  {id: 2, queue: :reminder, data: '{"user_id": 10}'},
                  {id: 3, queue: :reminder, data: '{"user_id": 15}'}
            ]

            allow(persister).to receive(:read) do |attrs|
               attrs[:data][:user_id] == 10 ? [tasks[1]] : nil
            end

            allow(persister).to receive(:delete)

            scheduler.cancel(:reminder, data: {user_id: 10})
            expect(persister).to have_received(:delete).with(2)
         end

         it 'should delete the task only on the given queue' do
            tasks = [
                  {id: 1, queue: :reminder, data: 'user_id: 5'},
                  {id: 2, queue: :greeting, data: 'user_id: 5'},
                  {id: 3, queue: :cleanup, data: 'user_id: 5'}
            ]

            allow(persister).to receive(:read) do |attrs|
               attrs[:queue] == :greeting.to_s ? [tasks[1]] : nil
            end

            allow(persister).to receive(:delete)

            scheduler.cancel(:greeting, data: {user_id: 5})
            expect(persister).to have_received(:delete).with(2)
         end

         it 'should complain if no task matches the given data' do
            allow(persister).to receive(:read).and_return([])

            [{data: {bogus: 6}},
             {data: 'missing data'}].each do |identifier|
               allow(persister).to receive(:delete)

               expect do
                  scheduler.cancel(:greeting, identifier)
               end.to raise_error(RuntimeError, "no task matches search: #{ identifier }")

               expect(persister).to_not have_received(:delete)
            end
         end

         it 'should complain if multiple task match the given data' do
            allow(persister).to receive(:read).and_return([{id: 1, queue: :reminder, run_at: 0},
                                                           {id: 2, queue: :reminder, run_at: 0}])

            allow(persister).to receive(:delete)

            [{run_at: 0},
             {queue: :reminder}].each do |identifier|
               expect do
                  scheduler.cancel(:greeting, identifier)
               end.to raise_error(RuntimeError, "multiple tasks match search: #{ identifier }")

               expect(persister).to_not have_received(:delete)
            end
         end
      end

      describe '#work' do
         let(:queue_names) { [:first, :second, :third] }
         let(:config) do
            Config.new do |config|
               queue_names.each { |name| config.define_queue(name, Test::MockTask, store: persister) }
            end
         end

         it 'should create a worker for only specified queues' do
            specified = [:first, :third]

            specified.each do |queue|
               allow(QueueWorker).to receive(:new).and_return(double("queue worker #{ queue }", work_one: nil))
            end

            scheduler.work(*specified)

            expect(QueueWorker).to have_received(:new).exactly(specified.length).times
         end

         it 'should create a worker for every queue definition by default' do
            allow(QueueWorker).to receive(:new)

            scheduler.work

            expect(QueueWorker).to have_received(:new).exactly(queue_names.length).times
         end
      end
   end

   describe Scheduler::UpdateProxy do
      let(:task_id) { 12358 }
      let(:task) do
         Task.new(TaskMetaData.new(queue: Queue.new(name: :test_queue, task_class: Test::MockTask), id: task_id),
                  Test::MockTask.new)
      end
      # need a queue double bc queues are frozen and can't be stubbed
      let(:queue) { double('queue', name: :some_queue, update: nil, fetch_task: task) }
      let(:update_proxy) { Scheduler::UpdateProxy.new(queue, identifier: {id: task_id}) }

      describe '#to' do
         it 'should ask the queue for the task' do
            update_proxy.to(run_at: Time.now)

            expect(queue).to have_received(:fetch_task).with(hash_including(id: task_id, queue: :some_queue))
         end

         it 'should update the found task' do
            allow(queue).to receive(:update)

            update_proxy.to(run_at: Time.now)

            expect(queue).to have_received(:update).with(task_id, anything)
         end

         it 'should update run_at and initial_run_at to the given time' do
            time = Time.parse('2022-05-01T05:40:00-06:00')

            allow(queue).to receive(:update)

            update_proxy.to(run_at: time)

            expect(queue).to have_received(:update).with(anything, hash_including(run_at:         time,
                                                                                  initial_run_at: time))
         end

         it 'should reschedule the run_at' do
            allow(task).to receive(:reschedule)

            update_proxy.to(run_at: 1234)

            expect(task).to have_received(:reschedule).with(run_at: 1234)
         end

         it 'should NOT reschedule run_at to nil' do
            allow(task).to receive(:reschedule)

            update_proxy.to(run_at: nil, expire_at: 0)

            expect(task).to_not have_received(:reschedule).with(run_at: nil)
         end

         it 'should reschedule the expire_at' do
            allow(task).to receive(:reschedule)

            update_proxy.to(expire_at: 4567)

            expect(task).to have_received(:reschedule).with(expire_at: 4567)
         end

         it 'should NOT reschedule expire_at to nil' do
            allow(task).to receive(:reschedule)

            update_proxy.to(run_at: 0, expire_at: nil)

            expect(task).to_not have_received(:reschedule).with(expire_at: nil)
         end

         it 'should complain if run_at nor expire_at are provided' do
            expect do
               update_proxy.to
            end.to raise_error(ArgumentError, 'you must provide at least :run_at or :expire_at')
         end

         it 'should not change id, queue, or data' do
            allow(queue).to receive(:update)

            update_proxy.to(run_at: Time.now)

            expect(queue).to have_received(:update).with(task_id, hash_excluding(:id, :data, :queue))
         end
      end
   end

   describe Scheduler::SerialWorking do
      let(:persister) { Test::Persister.new }
      let(:config) do
         queue_names = [:first, :second, :third]

         Config.new do |c|
            c.with_store(persister) do
               queue_names.each do |name|
                  c.define_queue(name, Test::MockTask)
               end
            end
         end
      end

      before do
         # TODO: remove when FakeFS is eliminated
         Pathname.new(QueueWorker::NULL_FILE).mkpath
      end

      # acts on each queue in series.
      # (useful for TDD)
      describe '#serially' do
         subject(:work_proxy) { Scheduler.new(config).work }
         let(:queue_workers) { work_proxy.workers }

         it 'should call QueueWorker#work_one on each queue worker' do
            queue_workers.each do |worker|
               allow(worker).to receive(:work_one)
            end
            work_proxy.serially

            expect(queue_workers).to all have_received(:work_one)
         end

         it 'should call QueueWorker#work_one the specified number of times' do
            queue_workers.each do |worker|
               allow(worker).to receive(:work_one)
            end

            work_proxy.serially(steps: 2)

            expect(queue_workers).to all have_received(:work_one).exactly(2).times
         end

         context 'log enabled'

         context 'log disabled'
      end
   end

   describe Scheduler::ThreadedWorking do
      let(:queue_names) { [:first, :second, :third] }

      let(:log_level) { false }
      let(:config) do
         Config.new do |c|
            c.with_store(Test::Persister.new) do
               queue_names.each do |name|
                  c.define_queue(name, Test::MockTask)
               end
            end
            c.log_with level: log_level
         end
      end

      let(:log_file) { config.log_dir / 'procrastinator.log' }

      before do
         # TODO: remove when FakeFS is eliminated
         Pathname.new(QueueWorker::NULL_FILE).mkpath

         # prevent actual threading during any testing
         allow(Thread).to receive(:new).and_raise('Must override Thread spawning in test')

         # need to stub fakefs flock because Logger uses it internally and FakeFS does not support it yet
         allow_any_instance_of(FakeFS::File).to receive(:flock)
      end

      # spawns a thread per queue and calls act on each queue worker
      # (useful for same-process one-offs like a manual intervention)
      describe '#threaded' do
         let(:log_level) { Logger::FATAL } # silence stdout logger in these tests

         subject(:work_proxy) { Scheduler.new(config).work(*queue_names) }

         context 'when in main thread' do
            it 'should spawn a new thread for each specified queue' do
               allow(Thread).to receive(:new).and_return(Test::MockThread.new)

               work_proxy.threaded

               expect(Thread).to have_received(:new).exactly(queue_names.size).times
            end

            it 'should wait for the threads to complete' do
               threads = [double('threadA', join: nil, kill: nil, alive?: true, thread_variable_get: nil),
                          double('threadB', join: nil, kill: nil, alive?: true, thread_variable_get: nil),
                          double('threadC', join: nil, kill: nil, alive?: true, thread_variable_get: nil)]
               allow(Thread).to receive(:new).and_return(*threads)

               threads.each do |thread|
                  allow(thread).to receive(:join)
               end

               work_proxy.threaded

               expect(threads).to all have_received(:join).once
            end

            it 'should respect the given timeout' do
               thread_double = Test::MockThread.new

               allow(Thread).to receive(:new).and_return(thread_double)

               n = 5
               allow(thread_double).to receive(:join)

               work_proxy.threaded(timeout: n)

               expect(thread_double).to have_received(:join).with(n).exactly(3).times # 3 for number of queues
            end

            context 'logging enabled' do
               let(:config) do
                  Config.new do |c|
                     queue_names.each do |name|
                        c.define_queue name, Test::MockTask
                     end
                  end
               end

               before do
                  allow(Thread).to receive(:new).and_return(Test::MockThread.new)
                  allow(Process).to receive(:pid).and_return(1234)
               end

               it 'should say it is starting threads' do
                  msg = 'Starting workers for queues: first, second, third'
                  expect { work_proxy.threaded }.to output(include(msg)).to_stderr

                  expect(log_file).to include_log_line 'INFO', msg
               end

               it 'should print the process pid' do
                  expect { work_proxy.threaded }.to output.to_stderr # silencing test output

                  expect(log_file).to include_log_line 'INFO', 'Procrastinator running. Process ID: 1234'
               end
            end
         end

         # ie. testing inside the child thread
         context 'when in child thread' do
            subject(:work_proxy) { Scheduler.new(config).work(:first) }
            let(:worker) { work_proxy.workers.first }

            before do
               allow(Thread).to receive(:new).and_yield(worker).and_return(Test::MockThread.new)

               # need to stub work for spying, but also because it uses an infiniloop
               allow(worker).to receive(:work!)
               allow(worker).to receive(:halt)
            end

            it 'should tell the queue worker to work' do
               work_proxy.threaded

               expect(worker).to have_received(:work!)
            end

            # worker#work loops indefinitely, but can be interrupted by shutdown.
            it 'should tell the worker to halt when interrupted' do
               work_proxy.threaded

               expect(worker).to have_received(:halt)
            end

            it 'should call halt after work normally' do
               work_proxy.threaded

               expect(worker).to have_received(:halt).once
            end

            # gently clean up the other threads when one sibling crashes
            it 'should call halt when errors happen' do
               err = 'dummy test error'
               allow(worker).to receive(:work!).and_raise(StandardError, err)

               expect { work_proxy.threaded }.to output.to_stderr # silencing terminal output

               expect(worker).to have_received(:halt).once
            end

            # Be aware that there is also a class-level version of abort_on_exception.
            # This is done per-instance to prevent accidental interactions with other gems, etc
            it 'should set this thread to raise errors to the parent' do
               allow(Thread.current).to receive(:abort_on_exception=)

               work_proxy.threaded

               expect(Thread.current).to have_received(:abort_on_exception=).with(true)
            end

            context 'when log disabled' do
               let(:log_level) { false }

               it 'should log to stderr but not to file' do
                  expect do
                     work_proxy.threaded
                  end.to output.to_stderr

                  expect(log_file).to_not exist
               end
            end

            context 'when log enabled' do
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
                  thread_double = Test::MockThread.new(name: worker.name, status: nil)

                  allow(Thread).to receive(:new).and_return(thread_double)

                  # need this one to be separately tested because the threads group is nil when immediately crashing on #work!
                  allow(thread_double).to receive(:join).and_raise(StandardError, 'dummy test error')

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
               allow(Thread).to receive(:new).and_return(Test::MockThread.new)

               allow(Signal).to receive(:trap)

               work_proxy.threaded

               expect(Signal).to have_received(:trap).with('INT')
            end

            it 'should register a SIGINT handler before calling join' do
               thread_double = Test::MockThread.new

               allow(Thread).to receive(:new).and_return(thread_double)

               expect(Signal).to receive(:trap).ordered
               expect(thread_double).to receive(:join).ordered.exactly(3).times # 3 for number of queues

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

            context 'when logging enabled' do
               let(:log_level) { Logger::INFO }

               before do
                  allow(Thread).to receive(:new).and_return(Test::MockThread.new)
               end

               it 'should say it is shutting down' do
                  allow(Signal).to receive(:trap).and_yield

                  msg1 = 'Halting worker threads...'
                  msg2 = 'Threads halted.'

                  expect do
                     work_proxy.threaded
                  end.to output(include(msg1, msg2)).to_stderr

                  expect(log_file).to include_log_line('INFO', msg1)
                                            .and include_log_line('INFO', msg2)
               end
            end
         end
      end
   end

   describe Scheduler::DaemonWorking do
      let(:queue_names) { [:first, :second, :third] }

      let(:persister) { Test::Persister.new }
      let(:log_level) { Logger::INFO }
      let(:config) do
         Config.new do |c|
            c.with_store(persister) do
               queue_names.each do |name|
                  c.define_queue(name, Test::MockTask)
               end
            end
            c.log_with level: log_level
         end
      end

      let(:log_file) { config.log_dir / 'procrastinator.log' }

      before do
         # prevent actual threading during any testing
         allow(Thread).to receive(:new).and_raise('Must override Thread spawning in test')

         # prevent the global at_exit handlers by default in testing
         allow_any_instance_of(Scheduler).to receive(:at_exit)

         # need to stub fakefs flock because Logger uses it internally and FakeFS does not support it yet
         allow_any_instance_of(FakeFS::File).to receive(:flock)
      end

      # takes over the current process and daemonizes itself.
      # (useful for normal background operations in production)
      describe '#daemonized!' do
         subject(:work_proxy) { Scheduler.new(config).work(:second) }

         before do
            # TODO: remove when FakeFS is eliminated
            Pathname.new(QueueWorker::NULL_FILE).mkpath

            allow(Process).to receive(:daemon).and_return(0)
         end

         it 'should call process daemon' do
            allow(Process).to receive(:daemon).and_return(0)

            work_proxy.daemonized!

            # no args means chdir to root and redirect all stdio to /dev/null
            expect(Process).to have_received(:daemon).with(no_args)
         end

         it 'should spawn queues workers in threaded mode' do
            allow(work_proxy).to receive(:threaded)

            work_proxy.daemonized!

            expect(work_proxy).to have_received(:threaded)
         end

         context 'process name' do
            before do
               allow(work_proxy).to receive(:system).with('pidof', anything, anything).and_return(false)
            end

            it 'should rename the daemon process based on the pidfile' do
               prog_name = 'vicky'

               allow(Process).to receive(:setproctitle)

               work_proxy.daemonized!("#{ prog_name }.pid")

               expect(Process).to have_received(:setproctitle).with(prog_name)
            end

            it 'should use a default process name' do
               allow(Process).to receive(:setproctitle)

               work_proxy.daemonized!('/var/run')

               expect(Process).to have_received(:setproctitle).with(Scheduler::DaemonWorking::PROG_NAME.downcase)
            end

            it 'should silently ask the system about another process' do
               prog_name = 'lemming'

               allow(work_proxy).to receive(:system)

               work_proxy.daemonized!("#{ prog_name }.pid")

               expect(work_proxy).to have_received(:system).with('pidof', prog_name, out: File::NULL)
            end

            context 'logging enabled' do
               let(:log_level) { Logger::INFO }

               it 'should log warning when an existing process has the same name' do
                  prog_name = 'lemming'

                  allow(work_proxy).to receive(:system).with('pidof', prog_name, anything).and_return(true)

                  msg = "Another process is already named '#{ prog_name }'. Consider the 'name:' keyword to distinguish."

                  work_proxy.daemonized!("#{ prog_name }.pid")

                  expect(log_file).to include_log_line 'WARN', msg
               end
            end
         end

         context 'pid file' do
            let(:pid_file) { Pathname.new 'pids/procrastinator.pid' }
            let(:default_basename) { 'procrastinator.pid' }

            # use fully-specified pid name as-is
            it 'should create pid file at the provided specific filename' do
               pid_file = Pathname.new('/tmp/atomic-coffee/beans.pid')
               work_proxy.daemonized!(pid_file)

               expect(pid_file).to exist
               expect(pid_file).to be_file
            end

            it 'should assume extensionless pid path is a directory' do
               pid_dir = Pathname.new('/tmp/atomic-coffee')
               work_proxy.daemonized!(pid_dir)

               expect(pid_dir).to exist
               expect(pid_dir).to be_directory
               expect(pid_dir / default_basename).to exist
            end

            # when not provided at all
            it 'should assume a default pid dir and name' do
               # wrap in new pathname to translate into FakeFS
               pid_path = Pathname.new(Scheduler::DaemonWorking::DEFAULT_PID_DIR)
               work_proxy.daemonized!
               expect(pid_path / default_basename).to exist
            end

            it 'should convert the path to absolute' do
               pid_path = Pathname.new('./up/../pid/something.pid')
               work_proxy.daemonized!(pid_path)
               expect(pid_path.expand_path).to exist
            end

            it 'should write its pid file' do
               pid = 12345
               allow(Process).to receive(:pid).and_return(pid)
               work_proxy.daemonized!(pid_file)

               file_content = File.read(pid_file)
               expect(file_content).to eq(pid.to_s)
            end

            it 'should clean up the pid file on exit' do
               # stub out at_exit to force it to run immediately
               allow(work_proxy).to receive(:at_exit).and_yield

               work_proxy.daemonized!

               expect(pid_file).to_not exist
            end

            it 'should be okay with the pid file not existing' do
               # stub out at_exit to force it to run immediately
               allow(work_proxy).to receive(:at_exit) do |&block|
                  pid_file.delete
                  block.call
               end

               work_proxy.daemonized!(pid_file)

               # stub out at_exit to force it to run immediately
               expect(work_proxy).to have_received(:at_exit)
            end

            context 'when prior process did not clean up its pid file' do
               before do
                  pid_file.dirname.mkpath
                  pid_file.write(1234)
                  allow(Process).to receive(:getpgid).and_raise Errno::ESRCH, 'No such process'
               end

               it 'should log warning about removing old pid file' do
                  msg = "Replacing old pid file of defunct process (pid 1234) at #{ pid_file.expand_path }."

                  work_proxy.daemonized!(pid_file)

                  expect(log_file).to include_log_line 'WARN', msg
               end
            end

            context 'when process already exists' do
               before do
                  pid_file.dirname.mkpath
                  pid_file.write(1234)
                  allow(Process).to receive(:getpgid).and_return 5678
               end

               it 'should ask about the process in the pid file' do
                  allow(Process).to receive(:getpgid)

                  expect do
                     work_proxy.daemonized!(pid_file)
                  end.to raise_error Scheduler::DaemonWorking::ProcessExistsError

                  expect(Process).to have_received(:getpgid).with(1234)
               end

               it 'should error out' do
                  expect do
                     work_proxy.daemonized!(pid_file)
                  end.to raise_error Scheduler::DaemonWorking::ProcessExistsError
               end

               it 'should log the process collision' do
                  hint = 'Either terminate that process or remove the pid file (if coincidental).'
                  msg  = "Another process (pid 1234) already exists for #{ pid_file.expand_path }. #{ hint }"

                  expect do
                     work_proxy.daemonized!(pid_file)
                  end.to raise_error Scheduler::DaemonWorking::ProcessExistsError, msg

                  expect(log_file).to include_log_line 'FATAL', msg
               end
            end
         end

         context 'status output' do
            let(:log_level) { Logger::INFO }
            let(:pid) { 12345 }

            before do
               allow(Process).to receive(:pid).and_return(pid)
            end

            it 'should open a log file' do
               log_path = config.log_dir / 'procrastinator.log'

               work_proxy.daemonized!

               expect(log_path).to exist
               expect(log_file).to include_log_line 'procrastinator', pid.to_s
            end

            it 'should print starting daemon' do
               work_proxy.daemonized!

               expect(log_file).to include_log_line 'INFO', 'Starting Procrastinator daemon...'
            end

            it 'should print a clean exit' do
               # stub out at_exit to force it to run inline
               allow(work_proxy).to receive(:at_exit).and_yield

               work_proxy.daemonized!

               expect(work_proxy).to have_received(:at_exit)
               expect(log_file).to include_log_line 'INFO', "Procrastinator (pid #{ pid }) halted."
            end

            it 'should log fatal errors' do
               msg = 'asplode'
               allow(Process).to receive(:daemon).and_raise msg

               expect do
                  work_proxy.daemonized!
               end.to raise_error RuntimeError, msg

               expect(log_file).to include_log_line 'FATAL', msg
            end

            context 'logging disabled' do
               let(:log_level) { false }

               it 'should create a null logger' do
                  work_proxy.daemonized!

                  expect(log_file).to_not exist
               end
            end
         end
      end

      context 'halt!' do
         let(:pid) { 12345 }

         before do
            allow(Process).to receive(:kill)
         end

         it 'should process kill the pid' do
            pid_file = Pathname.new 'procrastinator.pid'
            pid_file.write(pid)

            described_class.halt!(pid_file)

            expect(Process).to have_received(:kill).with('TERM', pid)
         end

         it 'should normalize the pid parameter' do
            pid_file = Pathname.new '/tmp/procrastinator.pid'
            pid_file.dirname.mkpath
            pid_file.write(pid)

            described_class.halt!(nil)

            expect(Process).to have_received(:kill).with('TERM', pid)
         end
      end
   end
end
