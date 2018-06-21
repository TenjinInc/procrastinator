require 'spec_helper'

module Procrastinator
   describe QueueWorker do
      let(:persister) {double('loader', read_tasks: [], update_task: nil, delete_task: nil)}

      describe '#initialize' do
         it 'should require a name' do
            expect {QueueWorker.new(task_class: nil, persister: nil)}.to raise_error(ArgumentError, 'missing keyword: name')
         end

         it 'should require a task_class' do
            expect {QueueWorker.new(name: nil, persister: nil)}.to raise_error(ArgumentError, 'missing keyword: task_class')
         end

         it 'should require a persister' do
            expect {QueueWorker.new(name: nil, task_class: nil)}.to raise_error(ArgumentError, 'missing keyword: persister')
         end

         it 'should store name as symbol' do
            [:email, :cleanup, 'a name'].each do |name|
               queue = QueueWorker.new(name: name, task_class: Test::Task::AllHooks, persister: persister)

               expect(queue.name).to eq name.to_s.gsub(/\s/, '_').to_sym
            end
         end

         it 'should require the name not be nil' do
            expect do
               QueueWorker.new(name: nil, task_class: Test::Task::AllHooks, persister: persister)
            end.to raise_error(ArgumentError, ':name may not be nil')
         end

         it 'should require the task class not be nil' do
            expect do
               QueueWorker.new(name: :queue, task_class: nil, persister: persister)
            end.to raise_error(ArgumentError, ':task_class may not be nil')
         end

         it 'should require the persister not be nil' do
            expect do
               QueueWorker.new(name: :queue, task_class: Test::Task::AllHooks, persister: nil)
            end.to raise_error(ArgumentError, ':persister may not be nil')
         end

         it 'should require the task class respond to .new' do
            expect do
               QueueWorker.new(name:       :queue,
                               task_class: double('struct or whatever'),
                               persister:  persister)
            end.to raise_error(ArgumentError, 'Task class must be initializable')
         end

         it 'should require the persister respond to #read_tasks' do
            expect do
               QueueWorker.new(name:       :queue,
                               task_class: Test::Task::AllHooks,
                               persister:  double('broken persister', delete_task: nil, update_task: nil))
            end.to raise_error(MalformedTaskPersisterError, 'The supplied IO object must respond to #read_tasks')
         end

         it 'should require the persister respond to #update_task' do
            expect do
               QueueWorker.new(name:       :queue,
                               task_class: Test::Task::AllHooks,
                               persister:  double('broken persister', read_tasks: []))
            end.to raise_error(MalformedTaskPersisterError, 'The supplied IO object must respond to #update_task')
         end

         it 'should require the persister respond to #delete_task' do
            expect do
               QueueWorker.new(name:       :queue,
                               task_class: Test::Task::AllHooks,
                               persister:  double('broken persister', read_tasks: [], update_task: nil))
            end.to raise_error(MalformedTaskPersisterError, 'The supplied IO object must respond to #delete_task')
         end

         it 'should accept a timeout' do
            (1..3).each do |t|
               queue = QueueWorker.new(name:       :queue,
                                       task_class: Test::Task::AllHooks,
                                       persister:  persister,
                                       timeout:    t)

               expect(queue.timeout).to eq t
            end
         end

         it 'should provide default timeout' do
            queue = QueueWorker.new(name:       :queue,
                                    task_class: Test::Task::AllHooks,
                                    persister:  persister)

            expect(queue.timeout).to eq QueueWorker::DEFAULT_TIMEOUT
         end

         it 'should accept a max_attempts' do
            (1..3).each do |t|
               queue = QueueWorker.new(name:         :queue,
                                       task_class:   Test::Task::AllHooks,
                                       persister:    persister,
                                       max_attempts: t)

               expect(queue.max_attempts).to eq t
            end
         end

         it 'should provide default max_attempts' do
            queue = QueueWorker.new(name:       :queue,
                                    task_class: Test::Task::AllHooks,
                                    persister:  persister)

            expect(queue.max_attempts).to eq QueueWorker::DEFAULT_MAX_ATTEMPTS
         end

         it 'should accept a update_period' do
            (1..3).each do |i|
               queue = QueueWorker.new(name:          :queue,
                                       task_class:    Test::Task::AllHooks,
                                       persister:     persister,
                                       update_period: i)

               expect(queue.update_period).to eq i
            end
         end

         it 'should provide a default update_period' do
            queue = QueueWorker.new(name:       :queue,
                                    task_class: Test::Task::AllHooks,
                                    persister:  persister)

            expect(queue.update_period).to eq QueueWorker::DEFAULT_UPDATE_PERIOD
         end

         it 'should accept a max_tasks' do
            (1..3).each do |i|
               queue = QueueWorker.new(name:       :queue,
                                       task_class: Test::Task::AllHooks,
                                       persister:  persister,
                                       max_tasks:  i)

               expect(queue.max_tasks).to eq i
            end
         end

         it 'should provide a default max_tasks' do
            queue = QueueWorker.new(name:       :queue,
                                    task_class: Test::Task::AllHooks,
                                    persister:  persister)

            expect(queue.max_tasks).to eq QueueWorker::DEFAULT_MAX_TASKS
         end
      end

      describe '#work' do
         it 'should wait for update_period' do
            [0.01, 0.02].each do |period|
               worker = QueueWorker.new(name:          :queue,
                                        task_class:    Test::Task::AllHooks,
                                        persister:     persister,
                                        update_period: period)

               expect(worker).to receive(:loop) do |&block|
                  block.call
               end

               expect(worker).to receive(:sleep).with(period)

               worker.work
            end
         end

         it 'should cyclically call #act' do
            worker = QueueWorker.new(name:          :queue,
                                     task_class:    Test::Task::AllHooks,
                                     persister:     persister,
                                     update_period: 0.1)

            allow(worker).to receive(:sleep) # stub sleep

            n_loops = 3

            # control looping, otherwise infiniloop by design
            allow(worker).to receive(:loop) do |&block|
               n_loops.times {block.call}
            end

            expect(worker).to receive(:act).exactly(n_loops).times

            worker.work
         end

         it 'should log fatal errors from act' do
            FakeFS do
               worker = QueueWorker.new(name:          :test,
                                        persister:     persister,
                                        task_class:    Test::Task::AllHooks,
                                        update_period: 0.1,
                                        log_dir:       'log/')

               err = 'some fatal error'

               allow(worker).to receive(:sleep) # stub sleep

               # control looping, otherwise infiniloop by design
               allow(worker).to receive(:loop) do |&block|
                  block.call
               end

               allow(worker).to receive(:act).and_raise(err)

               worker.work

               log = File.read('log/test-queue-worker.log')

               expect(log).to include('F, ') # default fatal error notation in Ruby logger
               expect(log).to include(err)
            end
         end
      end

      describe '#act' do
         context 'loading tasks' do
            it 'should pass the given queue to its persister' do
               [:email, :cleanup].each do |queue|
                  worker = QueueWorker.new(name:          queue,
                                           task_class:    Test::Task::AllHooks,
                                           persister:     persister,
                                           update_period: 0.01)

                  expect(persister).to receive(:read_tasks).with(queue)

                  worker.act
               end
            end

            it 'should sort tasks by run_at' do
               job1 = {id: 4, run_at: 1, initial_run_at: 0} # consider nil = 0
               job2 = {id: 5, run_at: 2, initial_run_at: 0}
               job3 = {id: 6, run_at: 3, initial_run_at: 0}

               task1 = Test::Task::AllHooks.new
               task2 = Test::Task::AllHooks.new
               task3 = Test::Task::AllHooks.new

               allow(Test::Task::AllHooks).to receive(:new).and_return(task1, task2, task3)

               persister = double('disorganized persister',
                                  read_tasks:  [job2, job3, job1],
                                  update_task: nil,
                                  delete_task: nil)

               worker = QueueWorker.new(name:          :queue,
                                        task_class:    Test::Task::AllHooks,
                                        persister:     persister,
                                        update_period: 0.01)

               expect(task1).to receive(:run).ordered
               expect(task2).to receive(:run).ordered
               expect(task3).to receive(:run).ordered

               worker.act
            end

            it 'should ignore tasks with nil run_at' do
               task1 = Test::Task::AllHooks.new
               task2 = Test::Task::AllHooks.new

               job1 = {id: 4, run_at: nil, initial_run_at: 0}
               job2 = {id: 5, run_at: 2, initial_run_at: 0}

               allow(Test::Task::AllHooks).to receive(:new).and_return(task2)

               persister = double('disorganized persister',
                                  read_tasks:  [job2, job1],
                                  update_task: nil,
                                  delete_task: nil)

               worker = QueueWorker.new(name:          :queue,
                                        task_class:    Test::Task::AllHooks,
                                        persister:     persister,
                                        update_period: 0.01)

               expect(task1).to_not receive(:run)
               expect(task2).to receive(:run)

               worker.act
            end

            it 'should reload tasks every cycle' do
               task1 = double('task1')
               task2 = double('task2')

               task1_duration = 4
               task2_duration = 6

               allow(task1).to receive(:run) do
                  Timecop.travel(task1_duration)
               end
               allow(task2).to receive(:run) do
                  Timecop.travel(task2_duration)
               end

               job1 = {run_at: 1}
               job2 = {run_at: 1}

               allow(persister).to receive(:read_tasks).and_return([job1], [job2])

               allow(Test::Task::AllHooks).to receive(:new).and_return(task1, task2)

               start_time = Time.now

               Timecop.freeze(start_time) do
                  worker = QueueWorker.new(name:          :queue,
                                           task_class:    Test::Task::AllHooks,
                                           persister:     persister,
                                           update_period: 0.00)

                  worker.act
                  worker.act

                  expect(Time.now.to_i).to eq start_time.to_i + task1_duration + task2_duration
               end
            end

            it 'should run a TaskWorker with all the data' do
               task_double = double('task', run: nil)
               task_data   = {run_at: 1}

               allow(Test::Task::AllHooks).to receive(:new).and_return(task_double)

               expect(TaskWorker).to receive(:new).with(satisfy do |param_hash|
                  task_data.all? do |k, v|
                     param_hash[k] == v
                  end
               end).and_call_original

               persister = double('persister', update_task: nil, delete_task: nil)
               allow(persister).to receive(:read_tasks).and_return([task_data])

               worker = QueueWorker.new(name:          :queue,
                                        task_class:    Test::Task::AllHooks,
                                        persister:     persister,
                                        update_period: 0)

               worker.act
            end

            it 'should pass the TaskWorker the task context' do
               task_double = double('task', run: nil)
               task_data   = {run_at: 1}
               task_worker = double('task worker')
               context     = double('context object')

               allow(Test::Task::AllHooks).to receive(:new).and_return(task_double)
               allow(TaskWorker).to receive(:new).and_return(task_worker)

               allow(task_worker).to receive(:successful?)
               allow(task_worker).to receive(:task_hash).and_return({})
               expect(task_worker).to receive(:work).with(hash_including(context: context))

               persister = double('persister', update_task: nil, delete_task: nil)
               allow(persister).to receive(:read_tasks).and_return([task_data])

               worker = QueueWorker.new(name:          :queue,
                                        task_class:    Test::Task::AllHooks,
                                        task_context:  context,
                                        persister:     persister,
                                        update_period: 0)

               worker.act
            end

            it 'should run a TaskWorker for each ready task' do
               task_data1 = {run_at: 1}
               task_data2 = {run_at: 1}
               task_data3 = {run_at: 1}

               expect(TaskWorker).to receive(:new).exactly(3).times.and_call_original

               persister = double('persister', update_task: nil, delete_task: nil)
               allow(persister).to receive(:read_tasks).and_return([task_data1, task_data2, task_data3])

               worker = QueueWorker.new(name:          :queue,
                                        task_class:    Test::Task::AllHooks,
                                        persister:     persister,
                                        update_period: 0)

               worker.act
            end

            it 'should not start any TaskWorkers for unready tasks' do
               now = Time.now

               task_data1 = {run_at: now}
               task_data2 = {run_at: now + 1}

               expect(TaskWorker).to receive(:new).ordered.and_call_original
               expect(TaskWorker).to_not receive(:new).ordered.and_call_original

               persister = double('persister', update_task: nil, delete_task: nil)
               allow(persister).to receive(:read_tasks).and_return([task_data1, task_data2])

               worker = QueueWorker.new(name:          :queue,
                                        task_class:    Test::Task::AllHooks,
                                        persister:     persister,
                                        update_period: 0)

               Timecop.freeze(now) do
                  worker.act
               end
            end

            it 'should not start more TaskWorkers than max_tasks' do
               task_data1 = {run_at: 1}
               task_data2 = {run_at: 2}

               expect(TaskWorker).to receive(:new).once.and_call_original

               persister = double('persister', update_task: nil, delete_task: nil)
               allow(persister).to receive(:read_tasks).and_return([task_data1, task_data2])

               worker = QueueWorker.new(name:          :queue,
                                        task_class:    Test::Task::AllHooks,
                                        persister:     persister,
                                        update_period: 0,
                                        max_tasks:     1)

               worker.act
            end

            it 'should pass in a logger to the logfile for this queue' do
               FakeFS do
                  task_worker = double('task_worker')
                  allow(task_worker).to receive(:successful?)
                  allow(task_worker).to receive(:to_hash).and_return({})

                  queue_name = :test_queue

                  task_double = double('task', run: nil)
                  task_data   = {run_at: 1, task: YAML.dump(task_double)}

                  allow(YAML).to receive(:load).and_return(task_double)

                  persister = double('persister', update_task: nil, delete_task: nil)
                  allow(persister).to receive(:read_tasks).and_return([task_data])

                  allow(TaskWorker).to receive(:new).and_return(task_worker)
                  allow(task_worker).to receive(:task_hash).and_return({})

                  expect(task_worker).to receive(:work).with(hash_including(:logger))

                  worker = QueueWorker.new(name:          queue_name,
                                           task_class:    Test::Task::AllHooks,
                                           persister:     persister,
                                           log_dir:       'log/',
                                           update_period: 0)

                  worker.act
               end
            end
         end

         context 'TaskWorker succeeds' do
            it 'should delete the task' do
               task_data = {
                     id:     double('id'),
                     run_at: 0
               }

               allow(persister).to receive(:read_tasks).and_return([task_data])

               worker = QueueWorker.new(name:          :queue,
                                        task_class:    Test::Task::AllHooks,
                                        persister:     persister,
                                        update_period: 0,
                                        max_tasks:     1)

               expect(persister).to receive(:delete_task).with(task_data[:id])

               worker.act
            end
         end

         context 'TaskWorker fails or fails For The Last Time' do
            # to do: it should promote captain Piett to admiral

            it 'should update the task' do
               [0, 1].each do |max_attempts|
                  task_data = {run_at: 0}
                  task_hash = {stub: :hash}

                  allow(persister).to receive(:read_tasks).and_return([task_data])

                  allow_any_instance_of(TaskWorker).to receive(:task_hash).and_return(task_hash)

                  worker = QueueWorker.new(name:          :queue,
                                           task_class:    Test::Task::Fail,
                                           persister:     persister,
                                           update_period: 0,
                                           max_attempts:  max_attempts)

                  expect(persister).to receive(:update_task).with(task_hash.merge(queue: worker.name))

                  worker.act
               end
            end
         end
      end

      describe '#start_log' do
         before do
            FakeFS.activate!

            if FakeFS.activated?
               FileUtils.rm_rf('/*')
            end
         end

         after do
            FakeFS.deactivate!
         end

         # falsey is the default for workers
         context 'logging directory falsey' do
            it 'should NOT create the log directory' do
               worker = QueueWorker.new(name:       :queue,
                                        task_class: Test::Task::AllHooks,
                                        persister:  persister)

               worker.start_log(false)

               expect(Dir.glob('/*')).to be_empty
            end

            it 'should NOT create a log file for this worker' do
               worker = QueueWorker.new(name:       :queue1,
                                        task_class: Test::Task::AllHooks,
                                        persister:  persister)

               worker.start_log(false)

               expect(File.file?('/queue1-queue-worker.log')).to be false
            end
         end

         context 'logging directory provided' do
            it 'should create the log directory if it does not exist' do
               worker = QueueWorker.new(name:       :queue1,
                                        task_class: Test::Task::AllHooks,
                                        persister:  persister)

               worker.start_log('some_dir/')

               expect(File.directory?('some_dir/')).to be true
            end

            it 'should log starting a queue worker' do
               [{parent: 10, child: 2000, queue: :test1},
                {parent: 30, child: 4000, queue: :test2}].each do |pid_hash|
                  parent_pid = pid_hash[:parent]
                  child_pid  = pid_hash[:child]
                  queue_name = pid_hash[:queue]

                  log_dir = 'some_dir'

                  worker = QueueWorker.new(name:       queue_name,
                                           task_class: Test::Task::AllHooks,
                                           persister:  persister)

                  allow(Process).to receive(:ppid).and_return(parent_pid)
                  allow(Process).to receive(:pid).and_return(child_pid)

                  worker.start_log(log_dir)

                  log_path = "#{log_dir}/#{worker.long_name}.log"

                  log_contents = File.read(log_path)

                  msgs = ['===================================',
                          "Started worker process, #{queue_name}-queue-worker, to work off queue #{queue_name}.",
                          "Worker pid=#{child_pid}; parent pid=#{parent_pid}.",
                          '===================================']

                  expect(log_contents).to include(msgs.join("\n"))
               end
            end

            it 'should append to the log file if it already exists' do
               log_dir = 'some_dir'

               worker = QueueWorker.new(name:       :queue1,
                                        task_class: Test::Task::AllHooks,
                                        persister:  persister)

               log_path = "#{log_dir}/#{worker.long_name}.log"

               existing_data = 'abcdef'

               FileUtils.mkdir_p(log_dir)
               File.open(log_path, 'a+') do |f|
                  f.write existing_data
               end

               worker.start_log(log_dir)

               expect(File.read(log_path)).to include(existing_data)
            end

            it 'should log at the provided level' do
               log_dir = 'log/'

               worker = QueueWorker.new(name:       :queue1,
                                        task_class: Test::Task::AllHooks,
                                        persister:  persister)

               worker.start_log(log_dir, level: Logger::FATAL)

               worker.log_parent_exit(ppid: 0, pid: 0)

               log_path = "#{log_dir}/#{worker.long_name}.log"

               expect(File.read(log_path)).to_not include('Terminated')
            end
         end
      end

      describe '#log_parent_exit' do
         it 'should complain if logger not built' do
            worker = QueueWorker.new(name:       :queue1,
                                     task_class: Test::Task::AllHooks,
                                     persister:  persister,
                                     log_dir:    nil)

            expect {worker.log_parent_exit(ppid: 0, pid: 1)}.to raise_error('Cannot log when logger not defined. Call #start_log first.')
         end

         it 'should log exiting when parent process disappears' do
            FakeFS do
               worker = QueueWorker.new(name:       :test,
                                        task_class: Test::Task::AllHooks,
                                        persister:  persister)

               worker.start_log('log/')

               [{parent: 10, child: 2000},
                {parent: 30, child: 4000}].each do |pid_hash|
                  parent_pid = pid_hash[:parent]
                  child_pid  = pid_hash[:child]

                  worker.log_parent_exit(ppid: parent_pid, pid: child_pid)

                  log_path = 'log/test-queue-worker.log'

                  expect(File.read(log_path)).to include("Terminated worker process (pid=#{child_pid}) due to main process (ppid=#{parent_pid}) disappearing.")
               end
            end
         end
      end
   end
end