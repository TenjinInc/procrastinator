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
               expect(persister).to receive(:create).with(include(queue: queue_name.to_s))

               scheduler.delay(queue_name)
            end
         end

         it 'should record a task with given run_at' do
            run_stamp = double('runstamp')

            expect(persister).to receive(:create).with(include(run_at: run_stamp))

            scheduler.delay(:reminders, run_at: double('time_object', to_i: run_stamp))
         end

         it 'should record a task with given expire_at' do
            expire_stamp = double('expirestamp')

            expect(persister).to receive(:create).with(include(expire_at: expire_stamp))

            scheduler.delay(:reminders, expire_at: double('time_object', to_i: expire_stamp))
         end

         it 'should record a task with serialized task data' do
            task_with_data = Class.new do
               include Task

               task_attr :data

               def run
               end
            end

            config = Config.new do |c|
               c.define_queue(:data_queue, task_with_data, store: persister)
            end

            scheduler = Scheduler.new(config)

            data = double('some_data')

            # these are, at the moment, all of the arguments the dev can pass in
            expect(persister).to receive(:create).with(include(data: JSON.dump(data)))

            scheduler.delay(:data_queue, data: data)
         end

         it 'should complain if they provide NO :data but the task expects it' do
            test_task = Class.new do
               include Procrastinator::Task

               task_attr :data

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

         it 'should complain if they provide :data but the task does NOT import it' do
            test_task = Class.new do
               include Procrastinator::Task

               def run
               end
            end

            config = Config.new do |c|
               c.define_queue(:data_queue, test_task, store: persister)
            end

            scheduler = Scheduler.new(config)

            err = <<~ERROR
               task #{ test_task } does not import :data. Add this in your class definition:
                     task_attr :data
            ERROR

            expect { scheduler.delay(:data_queue, data: 'some data') }.to raise_error(ArgumentError, err)
         end

         it 'should default run_at to now' do
            now = Time.now

            Timecop.freeze(now) do
               expect(persister).to receive(:create).with(include(run_at: now.to_i))

               scheduler.delay(:reminders)
            end
         end

         it 'should record initial_run_at and run_at to be equal' do
            time = Time.now

            expect(persister).to receive(:create).with(include(run_at: time.to_i, initial_run_at: time.to_i))

            scheduler.delay(:reminders, run_at: time)
         end

         it 'should convert run_at, initial_run_at, expire_at to ints' do
            expect(persister).to receive(:create).with(include(run_at: 0, initial_run_at: 0, expire_at: 1))

            scheduler.delay(:reminders,
                            run_at:    double('time', to_i: 0),
                            expire_at: double('time', to_i: 1))
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

         context 'only one queue' do
            let(:config) do
               Config.new do |c|
                  c.define_queue(:the_only_queue, test_task, store: persister)
               end
            end

            it 'should NOT require queue be provided if only one queue is defined' do
               expect { scheduler.delay(:reminders) }.to_not raise_error
            end

            it 'should assume the queue name if only one queue is defined' do
               expect(persister).to receive(:create).with(hash_including(queue: :the_only_queue.to_s))

               scheduler.delay(:reminders)
            end
         end
         context 'multiple queues' do
            let(:config) do
               Config.new do |c|
                  c.with_store persister do
                     c.define_queue(:first_queue, test_task)
                     c.define_queue(:second_queue, test_task)
                     c.define_queue(:third_queue, test_task)
                  end
               end
            end

            it 'should require queue be provided' do
               expect { scheduler.delay(run_at: 0) }.to raise_error ArgumentError, <<~ERR
                  queue must be specified when more than one is registered. Defined queues are: :first_queue, :second_queue, :third_queue
               ERR

               # also test the negative
               expect { scheduler.delay(:first_queue, run_at: 0) }.to_not raise_error
            end
         end

         it 'should complain when the given queue is not registered' do
            [:bogus, :other_bogus].each do |name|
               err = %[there is no :#{ name } queue registered. Defined queues are: :emails, :reminders]

               expect { scheduler.delay(name) }.to raise_error(ArgumentError, err)
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
            queue_names.each do |queue|
               expect(QueueWorker).to receive(:new).and_return(double("queue worker #{ queue }", work_one: nil))
            end

            scheduler.work
         end
      end
   end

   describe Scheduler::UpdateProxy do
      let(:test_task) { Test::Task::AllHooks }
      let(:persister) { Test::Persister.new }
      let(:config) do
         Config.new do |c|
            c.define_queue(:test_queue, test_task, store: persister)
         end
      end
      let(:identifier) { {id: 'id'} }
      let(:queue) { config.queue(name: :test_queue) }
      let(:update_proxy) { Scheduler::UpdateProxy.new(queue, identifier: identifier) }

      describe '#to' do
         before(:each) do
            allow(persister).to receive(:read).and_return([{id: 5}])
         end

         it 'should find the task matching the given information' do
            [{id: 5}, {data: {user_id: 5, appointment_id: 2}}].each do |identifier|
               update_proxy = Scheduler::UpdateProxy.new(queue, identifier: identifier)

               expect(persister).to receive(:read).with(identifier).and_return([double('task', '[]': 6)])

               update_proxy.to(run_at: 0)
            end
         end

         it 'should find the task matching the given serialized :data' do
            data = {user_id: 5, appointment_id: 2}

            update_proxy = Scheduler::UpdateProxy.new(queue, identifier: {data: data})

            expect(persister).to receive(:read).with(data: JSON.dump(data)).and_return([double('task', '[]': 6)])

            update_proxy.to(run_at: 0)
         end

         it 'should complain if no task matches the given information' do
            identifier = {bogus: 66}

            update_proxy = Scheduler::UpdateProxy.new(queue, identifier: identifier)

            [[], nil].each do |ret|
               allow(persister).to receive(:read).and_return(ret)

               expect do
                  update_proxy.to(run_at: 0)
               end.to raise_error(RuntimeError, "no task found matching #{ identifier }")
            end
         end

         it 'should complain if multiple tasks match the given information' do
            (3..5).each do |n|
               tasks = Array.new(n) { |i| double("task#{ i }") }

               allow(persister).to receive(:read).and_return(tasks)

               expect do
                  update_proxy.to(run_at: 0)
               end.to raise_error(RuntimeError, "too many (#{ n }) tasks match #{ identifier }. Found: #{ tasks }")
            end
         end

         it 'should complain if the given run_at would be after given expire_at' do
            time      = Time.now
            expire_at = Time.at 0

            expect do
               update_proxy.to(run_at: time, expire_at: expire_at)
            end.to raise_error(RuntimeError, "given run_at (#{ time }) is later than given expire_at (#{ expire_at })")
         end

         it 'should complain if the given run_at would be after original expire_at' do
            time      = Time.now
            expire_at = Time.at 0

            allow(persister).to receive(:read).and_return([TaskMetaData.new(expire_at: expire_at.to_i).to_h])

            expect do
               update_proxy.to(run_at: time)
            end.to raise_error(RuntimeError,
                               "given run_at (#{ time }) is later than saved expire_at (#{ expire_at.to_i })")
         end

         it 'should update the found task' do
            id = double('id')

            allow(persister).to receive(:read).and_return([{id: id}])

            expect(persister).to receive(:update).with(id, anything)

            update_proxy.to(run_at: Time.now)
         end

         it 'should update run_at and initial_run_at to the given time' do
            time = Time.now

            expect(persister).to receive(:update).with(anything, hash_including(run_at:         time.to_i,
                                                                                initial_run_at: time.to_i))

            update_proxy.to(run_at: time)
         end

         it 'should NOT update run_at and initial_run_at if run_at is not provided' do
            expect(persister).to receive(:update).with(anything, hash_excluding(:run_at, :initial_run_at))

            update_proxy.to(expire_at: Time.now)
         end

         it 'should complain if run_at nor expire_at are provided' do
            expect do
               update_proxy.to
            end.to raise_error(ArgumentError, 'you must provide at least :run_at or :expire_at')
         end

         it 'should update expire_at to the given time' do
            expire_at = Time.now + 10

            expect(persister).to receive(:update).with(anything, hash_including(expire_at: expire_at.to_i))

            update_proxy.to(run_at: Time.now, expire_at: expire_at)
         end

         it 'should NOT update expire_at if none is provided' do
            expect(persister).to receive(:update).with(anything, hash_excluding(:expire_at))

            update_proxy.to(run_at: Time.now)
         end

         it 'should not change id, queue, or data' do
            expect(persister).to receive(:update).with(anything, hash_excluding(:id, :data, :queue))

            update_proxy.to(run_at: Time.now)
         end

         it 'should reset attempts' do
            expect(persister).to receive(:update).with(anything, hash_including(attempts: 0))

            update_proxy.to(run_at: Time.now)
         end

         it 'should reset last_error and last_error_at' do
            expect(persister).to receive(:update).with(anything, hash_including(last_error:    nil,
                                                                                last_error_at: nil))

            update_proxy.to(run_at: Time.now)
         end
      end
   end

   describe Scheduler::WorkProxy do
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

      let(:main_logger) { Logger.new(StringIO.new) }

      before(:each) do
         # prevent actual threading during any testing
         allow(Thread).to receive(:new).and_raise('Must override Thread spawning in test')

         # prevent the global at_exit handlers by default in testing
         allow_any_instance_of(Scheduler::WorkProxy).to receive(:at_exit)
      end

      # acts on each queue in series.
      # (useful for TDD)
      context '#serially' do
         let(:queue_workers) do
            [queue_names.collect { |queue_name| double("queue worker #{ queue_name }") }]
         end
         let(:worker_proxy) { Scheduler::WorkProxy.new(queue_workers) }

         it 'should call QueueWorker#act on each queue worker' do
            queue_workers.each do |worker|
               expect(worker).to receive(:work_one)
            end
            worker_proxy.serially
         end

         it 'should call QueueWorker#act the specified number of times' do
            queue_workers.each do |worker|
               expect(worker).to receive(:work_one).exactly(2).times
            end

            worker_proxy.serially(steps: 2)
         end
      end

      # spawns a thread per queue and calls act on each queue worker
      # (useful for same-process one-offs like a manual intervention)
      context '#threaded' do
         let(:thread_double) { double('thread', join: nil, kill: nil, alive?: true, thread_variable_get: nil) }
         let(:queue_workers) do
            queue_names.collect do |queue_name|
               QueueWorker.new(queue: queue_name, config: config)
            end
         end
         let(:worker_proxy) { Scheduler::WorkProxy.new(queue_workers) }

         before(:each) do
            allow(Logger).to receive(:new).and_return(main_logger)
         end

         it 'should spawn a new thread for each specified queue' do
            expect(Thread).to receive(:new).exactly(queue_workers.size).times.and_return(thread_double)

            worker_proxy.threaded
         end

         it 'should wait for the threads to complete' do
            threads = [double('threadA', join: nil, kill: nil, alive?: true, thread_variable_get: nil),
                       double('threadB', join: nil, kill: nil, alive?: true, thread_variable_get: nil),
                       double('threadC', join: nil, kill: nil, alive?: true, thread_variable_get: nil)]
            allow(Thread).to receive(:new).and_return(*threads)

            threads.each do |thread|
               expect(thread).to receive(:join).once
            end

            worker_proxy.threaded
         end

         it 'should respect the given timeout' do
            allow(Thread).to receive(:new).and_return(thread_double)

            n = 5
            expect(thread_double).to receive(:join).with(n)

            worker_proxy.threaded(timeout: n)
         end

         it 'should say it is starting threads' do
            allow(Thread).to receive(:new).and_return(thread_double)

            expect(main_logger).to receive(:info).with('Starting worker threads...')
            allow(main_logger).to receive(:info).with(anything)
            worker_proxy.threaded
         end

         # ie. testing inside the child thread
         context 'child thread' do
            let(:worker) { queue_workers.first }
            let(:worker_proxy) { Scheduler::WorkProxy.new([worker]) }

            before(:each) do
               allow(Logger).to receive(:new).and_return(main_logger)

               allow(Thread).to receive(:new).and_yield(worker).and_return(thread_double)

               allow(worker).to receive(:work) # need to stub work because it uses an inifiniloop
               allow(worker).to receive(:halt)
            end

            it 'should tell the queue worker to work' do
               expect(worker).to receive(:work)

               worker_proxy.threaded
            end

            # worker#work loops indefinitely, but can be interrupted by shutdown.
            it 'should tell the worker to halt when interrupted' do
               expect(worker).to receive(:halt)

               worker_proxy.threaded
            end

            # this is a backstop to the queue worker's internal logging, just in case that fails
            it 'should warn about errors' do
               msg = 'Crash detected in queue worker thread.'
               err = 'dummy test error'
               allow(worker).to receive(:work).and_raise(StandardError, err)

               expect(main_logger).to receive(:fatal).with(include(msg, # generic crash alert
                                                                   err, # real error message
                                                                   '<module:Procrastinator>')) # backtrace

               worker_proxy.threaded
            end

            it 'should warn about errors with the crashed queue name' do
               allow(Thread).to receive(:new).and_return(thread_double)

               # need this one to be separately tested because the threads group is nil when immediately crashing on #work
               err = 'dummy test error'
               allow(thread_double).to receive(:join).and_raise(StandardError, err)

               allow(thread_double).to receive(:status).and_return(nil)
               allow(thread_double).to receive(:thread_variable_get).and_return(worker.name)

               expect(main_logger).to receive(:fatal).with(include("Crashed thread: #{ worker.name }")) # backtrace

               worker_proxy.threaded
            end

            it 'should call halt after work normally' do
               expect(worker).to receive(:halt).once

               worker_proxy.threaded
            end

            # gently clean up the other threads when one sibling crashes
            it 'should call halt when errors happen' do
               err = 'dummy test error'
               allow(queue_workers.first).to receive(:work).and_raise(StandardError, err)

               expect(worker).to receive(:halt).once

               # expect do
               worker_proxy.threaded
               # end.to raise_error(StandardError, err)
            end

            # Be aware that there is also a class-level version of abort_on_exception.
            # This is done per-instance to prevent accidental interactions with other gems, etc
            it 'should set this thread to raise errors to the parent' do
               expect(Thread.current).to receive(:abort_on_exception=).with(true)

               worker_proxy.threaded
            end
         end

         context 'SIGINT' do
            it 'should register a SIGINT handler' do
               allow(Thread).to receive(:new).and_return(thread_double)

               expect(Signal).to receive(:trap).with('INT')

               worker_proxy.threaded
            end

            it 'should register a SIGINT handler before calling join' do
               allow(Thread).to receive(:new).and_return(thread_double)

               expect(Signal).to receive(:trap).ordered
               expect(thread_double).to receive(:join).ordered

               worker_proxy.threaded
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

               worker_proxy.threaded

               expect(thread_a).to receive(:kill).once
               expect(thread_b).to_not receive(:kill)
               expect(thread_c).to receive(:kill).once
               signal_block&.call
            end

            it 'should say it is shutting down' do
               thread_a = double('threadA', join: nil, kill: nil, alive?: true, thread_variable_get: nil)
               allow(Thread).to receive(:new).and_return(thread_a)

               signal_block = nil
               allow(Signal).to receive(:trap) do |&block|
                  signal_block = block
               end

               allow(main_logger).to receive(:info).with(anything)
               expect(main_logger).to receive(:info).with('Halting worker threads...')
               expect(main_logger).to receive(:info).with('Threads halted.')
               worker_proxy.threaded
               signal_block&.call
            end
         end
      end

      # takes over the current process and daemonizes itself.
      # (useful for normal background operations in production)
      context '#daemonized!' do
         let(:worker_proxy) do
            Scheduler::WorkProxy.new([QueueWorker.new(queue:  :test_queue,
                                                      config: config)])
         end

         before(:each) do
            allow(Logger).to receive(:new).and_return(main_logger)
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

            it 'should NOT run the given block' do
               allow(worker_proxy).to receive(:fork).and_return(1234)

               was_run = false
               expect do
                  worker_proxy.daemonized! do
                     was_run = true
                  end
               end.to raise_error(SystemExit)

               expect(was_run).to eq false
            end
         end
         context 'child process' do
            before(:each) do
               allow(worker_proxy).to receive(:fork).and_return(nil)
               allow(worker_proxy).to receive(:threaded)
               allow(worker_proxy).to receive(:loop).and_yield
            end

            # prevents pointing to a pwd inherited from a manual terminal run (which might disappear)
            it 'should chdir to root' do
               expect(Dir).to receive(:chdir).with('/')
               worker_proxy.daemonized!
            end

            it 'should spawn queues workers in threaded mode' do
               expect(worker_proxy).to receive(:threaded)

               worker_proxy.daemonized!
            end

            it 'should run the given block' do
               was_run = false
               worker_proxy.daemonized! do
                  was_run = true
               end

               expect(was_run).to eq true
            end

            # not sure this is actually necessary to test, so leaving just as a note:
            #    it 'should respond to SIGTERM to exit cleanly'

            context 'process name' do
               before(:each) do
                  allow(worker_proxy).to receive(:system).with('pidof', anything).and_return(false)
               end

               it 'should rename the daemon process' do
                  procname = 'deemins'

                  expect(Process).to receive(:setproctitle).with(procname)

                  worker_proxy.daemonized!(name: procname)
               end

               it 'should warn if the process name is too long' do
                  maxlen       = Scheduler::WorkProxy::MAX_PROC_LEN
                  max_procname = 'a' * maxlen
                  name         = "#{ max_procname }b"

                  msg = "process name is longer than max length (#{ maxlen }). Trimming to fit."
                  expect(main_logger).to receive(:warn).with(msg)

                  worker_proxy.daemonized!(name: name)
               end

               it 'should warn trim long process names to fit' do
                  maxlen       = Scheduler::WorkProxy::MAX_PROC_LEN
                  max_procname = 'z' * maxlen

                  expect(Process).to receive(:setproctitle).with(max_procname)

                  worker_proxy.daemonized!(name: "#{ max_procname }more")
               end

               it 'should warn when an existing process has the same name' do
                  procname = 'lemming'

                  expect(worker_proxy).to receive(:system).with('pidof', procname).and_return(true)

                  msg = "a process is already named '#{ procname }'. Consider the 'name:' argument to distinguish."

                  expect(main_logger).to receive(:warn).with(msg)

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
                  expect(pid_dir / Scheduler::WorkProxy::DEFAULT_PID_FILE).to exist
               end

               it 'should use a default pid dir' do
                  worker_proxy.daemonized!
                  pid_path = Scheduler::WorkProxy::DEFAULT_PID_DIR / Scheduler::WorkProxy::DEFAULT_PID_FILE
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
                  expect(main_logger).to receive(:info).with('Starting Procrastinator daemon...')
                  expect(main_logger).to receive(:info).with(anything)

                  worker_proxy.daemonized!
               end

               it 'should print the daemon pid' do
                  [1234, 5678].each do |pid|
                     allow(Process).to receive(:pid).and_return(pid)

                     expect(main_logger).to receive(:info).with(anything)
                     expect(main_logger).to receive(:info).with("Procrastinator running. Process ID: #{ pid }")

                     worker_proxy.daemonized!
                  end
               end

               it 'should print a clean exit' do
                  [1234, 5678].each do |pid|
                     allow(Process).to receive(:pid).and_return(pid)

                     # stub out at_exit to force it to run immediately
                     expect(worker_proxy).to receive(:at_exit).and_yield

                     allow(main_logger).to receive(:info)
                     expect(main_logger).to receive(:info).with("Procrastinator (pid #{ pid }) halted.")

                     worker_proxy.daemonized!
                  end
               end
            end
         end
      end
   end
end
