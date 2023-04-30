# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe Queue do
      let(:test_task) { Test::MockTask }
      let(:persister) { fake_persister([{id: 1, run_at: 1}]) }

      describe '#initialize' do
         let(:basic_queue) do
            Queue.new(name: :test_name, task_class: test_task, store: persister)
         end

         it 'should require a name' do
            expect { Queue.new(task_class: nil) }.to raise_error(ArgumentError, 'missing keyword: name')
         end

         it 'should require a task_class' do
            expect { Queue.new(name: '') }.to raise_error(ArgumentError, 'missing keyword: task_class')
         end

         it 'should convert the queue name to a symbol' do
            {
                  space_before:  ' space_before',
                  space_after:   'space_after ',
                  space_inside:  'space inside',
                  double_space:  'double  space',
                  special_chars: 'special:[]!@#$%^&*()-=+<>\'",./?`~chars'
            }.each do |expected, input|
               queue = Queue.new(name:       input,
                                 task_class: test_task, store: persister)

               expect(queue.name).to eq expected
            end
         end

         it 'should require the name not be nil' do
            expect do
               Queue.new(name: nil, task_class: test_task)
            end.to raise_error(ArgumentError, ':name cannot be nil')
         end

         it 'should require the task class not be nil' do
            expect do
               Queue.new(name: :test_name, task_class: nil)
            end.to raise_error(ArgumentError, ':task_class cannot be nil')
         end

         it 'should require the task class respond to .new' do
            expect do
               Queue.new(name:       :test_name,
                         task_class: double('struct or whatever'))
            end.to raise_error(ArgumentError, 'Task class must be initializable')
         end

         context 'task store' do
            it 'should accept a task store' do
               storage = fake_persister([])
               queue   = Queue.new(name: :test_name, task_class: test_task, store: storage)

               expect(queue.task_store).to eq storage
            end

            it 'should alias storage and store' do
               queue = Queue.new(name: :test_name, task_class: test_task, store: persister)

               expect(queue.store).to eq persister
               expect(queue.storage).to eq persister
            end

            it 'should reject nil storage' do
               expect do
                  Queue.new(name: :test_name, task_class: test_task, store: nil)
               end.to raise_error(ArgumentError, ':store cannot be nil')
            end

            it 'should complain if the task store does not respond to #read' do
               bad_store = double('block', create: nil, update: nil, delete: nil)

               err = "task store #{ bad_store.class } must respond to #read"

               expect do
                  Queue.new(name: :test_name, task_class: test_task, store: bad_store)
               end.to raise_error(MalformedTaskStoreError, err)
            end

            it 'should complain if the task store does not respond to #create' do
               bad_store = double('block', read: nil, update: nil, delete: nil)

               err = "task store #{ bad_store.class } must respond to #create"

               expect do
                  Queue.new(name: :test_name, task_class: test_task, store: bad_store)
               end.to raise_error(MalformedTaskStoreError, err)
            end

            it 'should complain if the task store does not respond to #update' do
               bad_store = double('block', read: nil, create: nil, delete: nil)

               err = "task store #{ bad_store.class } must respond to #update"

               expect do
                  Queue.new(name: :test_name, task_class: test_task, store: bad_store)
               end.to raise_error(MalformedTaskStoreError, err)
            end

            it 'should complain if the task store does not respond to #delete' do
               bad_store = double('block', read: nil, create: nil, update: nil)

               err = "task store #{ bad_store.class } must respond to #delete"

               expect do
                  Queue.new(name: :test_name, task_class: test_task, store: bad_store)
               end.to raise_error(MalformedTaskStoreError, err)
            end
         end

         it 'should accept a timeout' do
            (1..3).each do |t|
               queue = Queue.new(name:    :test_name, task_class: test_task, store: persister,
                                 timeout: t)

               expect(queue.timeout).to eq t
            end
         end

         it 'should provide a default timeout' do
            expect(basic_queue.timeout).to eq Queue::DEFAULT_TIMEOUT
         end

         it 'should complain when timeout is negative' do
            expect do
               Queue.new(name:    :test_name, task_class: test_task, store: persister,
                         timeout: -1)
            end.to raise_error(ArgumentError, ':timeout cannot be negative')
         end

         it 'should accept a max_attempts' do
            (1..3).each do |t|
               queue = Queue.new(name:         :test_name, task_class: test_task, store: persister,
                                 max_attempts: t)

               expect(queue.max_attempts).to eq t
            end
         end

         it 'should provide default max_attempts' do
            expect(basic_queue.max_attempts).to eq Queue::DEFAULT_MAX_ATTEMPTS
         end

         it 'should accept an update_period' do
            (1..3).each do |i|
               queue = Queue.new(name:          :test_name,
                                 task_class:    test_task,
                                 store:         persister,
                                 update_period: i)

               expect(queue.update_period).to eq i
            end
         end

         it 'should provide a default update_period' do
            expect(basic_queue.update_period).to eq Queue::DEFAULT_UPDATE_PERIOD
         end

         context 'task class interface' do
            it 'should complain if task does not support #run' do
               task_class = Class.new do
                  # bad task
               end

               expect do
                  Queue.new(name: :test_queue, task_class: task_class)
               end.to raise_error(MalformedTaskError, "task #{ task_class } does not support #run method")
            end

            it 'should complain if task #run expects parameters' do
               klass = Class.new do
                  def run(_params)
                  end
               end

               err = "task #{ klass } cannot require parameters to its #run method"

               expect do
                  Queue.new(name: :test_queue, task_class: klass)
               end.to raise_error(MalformedTaskError, err)
            end

            # Data is verified on calls to #defer and is therefore optional in the duck-typing interface
            it 'should NOT complain if task does not accept a data packet' do
               task_class = Class.new do
                  attr_accessor :scheduler, :container, :logger

                  def run
                  end
               end

               expect do
                  Queue.new(name: :test_queue, task_class: task_class)
               end.to_not raise_error
            end

            it 'should complain if task does not accept a logger' do
               task_class = Class.new do
                  attr_accessor :data, :scheduler, :container

                  def run
                  end
               end

               expect do
                  Queue.new(name: :test_queue, task_class: task_class)
               end.to raise_error MalformedTaskError, <<~ERR
                  Task handler is missing a logger accessor. Add this to the #{ task_class } class definition:
                     attr_accessor :logger, :container, :scheduler
               ERR
            end

            it 'should complain if task does not accept a scheduler' do
               task_class = Class.new do
                  attr_accessor :data, :container, :logger

                  def run
                  end
               end

               expect do
                  Queue.new(name: :test_queue, task_class: task_class)
               end.to raise_error MalformedTaskError, <<~ERR
                  Task handler is missing a scheduler accessor. Add this to the #{ task_class } class definition:
                     attr_accessor :logger, :container, :scheduler
               ERR
            end

            it 'should complain if task does not accept a container' do
               task_class = Class.new do
                  attr_accessor :data, :scheduler, :logger

                  def run
                  end
               end

               expect do
                  Queue.new(name: :test_queue, task_class: task_class)
               end.to raise_error MalformedTaskError, <<~ERR
                  Task handler is missing a container accessor. Add this to the #{ task_class } class definition:
                     attr_accessor :logger, :container, :scheduler
               ERR
            end

            it 'should complain if task does NOT accept 1 parameter to #success' do
               no_arg_success = Class.new do
                  attr_accessor :container, :logger, :scheduler

                  def run
                  end

                  def success
                  end
               end

               multi_arg_success = Class.new do
                  attr_accessor :container, :logger, :scheduler

                  def run
                  end

                  def success(_arg1, _arg2)
                  end
               end

               [no_arg_success, multi_arg_success].each do |klass|
                  err = "task #{ klass } must accept 1 parameter to its #success method"

                  expect do
                     Queue.new(name: :test_queue, task_class: klass)
                  end.to raise_error(MalformedTaskError, err)
               end
            end

            it 'should complain if task does NOT accept 1 parameter in #fail' do
               no_arg_fail = Class.new do
                  attr_accessor :container, :logger, :scheduler

                  def run
                  end

                  def fail
                  end
               end

               multi_arg_fail = Class.new do
                  attr_accessor :container, :logger, :scheduler

                  def run
                  end

                  def fail(_arg1, _arg2)
                  end
               end

               [no_arg_fail, multi_arg_fail].each do |klass|
                  err = "task #{ klass } must accept 1 parameter to its #fail method"

                  expect do
                     Queue.new(name: :test_queue, task_class: klass)
                  end.to raise_error(MalformedTaskError, err)
               end
            end

            it 'should complain if task does NOT accept 1 parameter in #final_fail' do
               no_arg_final_fail = Class.new do
                  attr_accessor :container, :logger, :scheduler

                  def run
                  end

                  def final_fail
                  end
               end

               multi_arg_final_fail = Class.new do
                  attr_accessor :container, :logger, :scheduler

                  def run
                  end

                  def final_fail(_arg1, _arg2)
                  end
               end

               [no_arg_final_fail, multi_arg_final_fail].each do |klass|
                  err = "task #{ klass } must accept 1 parameter to its #final_fail method"

                  expect do
                     Queue.new(name: :test_queue, task_class: klass)
                  end.to raise_error(MalformedTaskError, err)
               end
            end
         end

         # queue definitions are immutable for additional thread safety
         it 'should freeze itself' do
            expect(basic_queue).to be_frozen
         end
      end

      describe 'next_task' do
         let(:task_class) do
            Class.new do
               attr_accessor :container, :logger, :scheduler

               def run
               end
            end
         end

         # need a nonzero run_at to not be ignored when loading tasks
         let(:dummy_run_at) { '2022-09-03T09:37:00-06:00' }

         it 'should restore the stored scheduling metadata' do
            saved_metadata = {
                  id:             double('id'),
                  run_at:         '2022-09-03T09:37:00-06:00',
                  initial_run_at: '2022-09-01T08:30:00-06:00',
                  expire_at:      '2022-12-15T12:00:00-06:00'
            }

            queue = Queue.new(name: :email, task_class: test_task, store: fake_persister([saved_metadata]))

            task = queue.next_task

            expect(task&.id).to eq saved_metadata[:id]
            expect(task&.run_at).to eq Time.parse(saved_metadata[:run_at])
            expect(task&.initial_run_at).to eq Time.parse(saved_metadata[:initial_run_at])
            expect(task&.expire_at).to eq Time.parse(saved_metadata[:expire_at])
         end

         it 'should restore the stored failure metadata' do
            saved_metadata = {
                  run_at:       dummy_run_at,
                  attempts:     8,
                  last_error:   double('last error'),
                  last_fail_at: Time.now
            }

            queue = Queue.new(name: :email, task_class: test_task, store: fake_persister([saved_metadata]))

            task = queue.next_task

            expect(task&.attempts).to eq saved_metadata[:attempts]
            expect(task&.last_error).to eq saved_metadata[:last_error]
            expect(task&.last_fail_at).to eq saved_metadata[:last_fail_at]
         end

         it 'should restore the stored task data' do
            data = {some_data: 5}

            saved_metadata = {
                  run_at: dummy_run_at,
                  data:   JSON.dump(data)
            }

            queue = Queue.new(name: :email, task_class: test_task, store: fake_persister([saved_metadata]))

            task = queue.next_task

            expect(task&.data).to eq data
         end

         it 'should pass the TaskMetaData the queue definition' do
            queue = Queue.new(name: :email, task_class: task_class, store: fake_persister([{run_at: dummy_run_at}]))

            task = queue.next_task
            expect(task&.queue).to eq queue
         end

         it 'should ignore any unused or unknown fields' do
            task_data = {id:     1,
                         queue:  'some_queue',
                         run_at: dummy_run_at,
                         bogus:  double('bogus')}

            queue = Queue.new(name: :email, task_class: task_class, store: fake_persister([task_data]))

            expect { queue.next_task }.to_not raise_error
         end

         it 'should filter tasks by the queue name' do
            persister = fake_persister([{id: 1, run_at: dummy_run_at, queue: :reminder},
                                        {id: 2, run_at: dummy_run_at, queue: :email},
                                        {id: 3, run_at: dummy_run_at, queue: :welcome}])

            queue = Queue.new(name: :email, task_class: task_class, store: persister)

            expect(persister).to receive(:read).with(queue: queue.name)

            queue.next_task
         end

         it 'should ignore unready tasks' do
            now = Time.now

            task_meta1 = {id: 1, run_at: now + 1}
            task_meta2 = {id: 2, run_at: now}
            task_meta3 = {id: 1, run_at: now + 3}

            queue = Queue.new(name:       :email,
                              task_class: task_class,
                              store:      fake_persister([task_meta1,
                                                          task_meta2,
                                                          task_meta3]))

            Timecop.freeze(now) do
               task = queue.next_task
               expect(task&.id).to eq 2
            end
         end

         it 'should ignore tasks with nil run_at' do
            job1 = {id: 4, run_at: nil, initial_run_at: dummy_run_at}
            job2 = {id: 5, run_at: dummy_run_at, initial_run_at: dummy_run_at}

            persister = double('disorganized persister',
                               read:   [job2, job1],
                               create: nil,
                               update: nil,
                               delete: nil)

            queue = Queue.new(name: :email, task_class: task_class, store: persister)

            task = queue.next_task
            expect(task&.id).to eq 5
         end

         it 'should sort tasks by run_at' do
            job1 = {id: 1, run_at: '2022-09-01T00:00:30-06:00', initial_run_at: 0}
            job2 = {id: 2, run_at: '2022-09-01T00:00:00-06:00', initial_run_at: 0}
            job3 = {id: 3, run_at: '2022-09-01T00:00:50-06:00', initial_run_at: 0}

            persister = double('disorganized persister',
                               read:   [job2, job1, job3],
                               create: nil,
                               update: nil,
                               delete: nil)

            queue = Queue.new(name: :email, task_class: task_class, store: persister)

            task = queue.next_task

            expect(task&.id).to eq 2
         end

         it 'should create a new task handler instance' do
            queue = Queue.new(name: :test_queue, task_class: task_class, store: persister)

            expect(Task).to receive(:new).with(instance_of(TaskMetaData), instance_of(task_class))

            queue.next_task
         end

         it 'should provide no arguments to the constructor' do
            queue = Queue.new(name: :test_queue, task_class: task_class, store: persister)

            expect(task_class).to receive(:new).with(no_args).and_call_original

            queue.next_task
         end

         it 'should create a logged task' do
            Pathname.new(QueueWorker::NULL_FILE).mkpath # TODO: remove when FakeFS is eliminated

            config = Config.new do |c|
               c.define_queue(:fast_queue, test_task, update_period: 0, store: fake_persister([{run_at: 1}]))
            end

            expect(LoggedTask).to receive(:new).with(instance_of(Task),
                                                     hash_including(logger: instance_of(Logger))).and_call_original
            worker = QueueWorker.new(queue: :fast_queue, config: config)

            worker.work_one
         end

         context 'dependency injection' do
            let(:task) { task_class.new }
            let(:meta) { TaskMetaData.new }
            let(:queue) { Queue.new(name: :test_queue, task_class: task_class, store: persister) }

            before(:each) do
               allow(task_class).to receive(:new).and_return(task)
            end

            it 'should provide the data packet to the new task instance if requested' do
               task_class = Class.new do
                  attr_accessor :data, :logger, :container, :scheduler

                  def run
                  end
               end

               task = task_class.new

               allow(task_class).to receive(:new).and_return(task)

               data      = 'data here'
               persister = fake_persister([{id: 2, run_at: 2, data: JSON.dump(data)}])

               queue = Queue.new(name: :test_queue, task_class: task_class, store: persister)

               expect(task).to receive(:data=).with(data)

               queue.next_task
            end

            it 'should provide the container to the new task instance' do
               container = double('container')

               expect(task).to receive(:container=).with(container)

               queue.next_task(container: container)
            end

            it 'should provide the logger to the new task instance' do
               logger = Logger.new(StringIO.new)

               expect(task).to receive(:logger=).with(logger)

               queue.next_task(logger: logger)
            end

            it 'should provide the scheduler to the new task instance' do
               scheduler = double('scheduler')

               expect(task).to receive(:scheduler=).with(scheduler)

               queue.next_task(scheduler: scheduler)
            end
         end
      end

      describe 'create' do
         let(:task_with_data) do
            Class.new do
               attr_accessor :data, :logger, :container, :scheduler

               def run
               end
            end
         end

         let(:task_without_data) do
            Class.new do
               attr_accessor :logger, :container, :scheduler

               def run
               end
            end
         end

         let(:required_args) { {run_at: nil, expire_at: nil, data: nil} }

         it 'should forward the call to the storage' do
            queue = Queue.new(name: :test_queue, task_class: task_without_data, store: persister)

            expect(persister).to receive(:create)

            queue.create(required_args)
         end

         it 'should record a task with serialized task data' do
            queue = Queue.new(name: :test_queue, task_class: task_with_data, store: persister)

            data = double('some_data')

            # these are, at the moment, all of the arguments the dev can pass in
            expect(persister).to receive(:create).with(include(data: JSON.dump(data)))

            queue.create(required_args.merge(data: data))
         end

         it 'should complain if they provide :data but the task does NOT import it' do
            queue = Queue.new(name: :test_queue, task_class: task_without_data)

            err = <<~ERROR
               found unexpected :data argument. Either do not provide :data when scheduling a task,
               or add this in the #{ task_without_data } class definition:
                     attr_accessor :data
            ERROR

            expect do
               queue.create(required_args.merge(data: double('something')))
            end.to raise_error(MalformedTaskError, err)
         end

         it 'should complain if they do NOT provide :data and the task expects it' do
            queue = Queue.new(name: :test_queue, task_class: task_with_data)

            err = "task #{ task_with_data } expects to receive :data. Provide :data to #delay."

            expect { queue.create(required_args.merge(data: nil)) }.to raise_error(ArgumentError, err)
         end
      end

      describe '#fetch_task' do
         let(:queue) { Queue.new(name: :test_queue, task_class: Test::MockTask, store: persister) }

         it 'should request the task matching the given information' do
            [{id: 5}, {data: {user_id: 5, appointment_id: 2}}].each do |identifier|
               expect(persister).to receive(:read).with(identifier).and_return([{id: 1, run_at: 2}])

               queue.fetch_task(identifier)
            end
         end

         it 'should find the task matching the given serialized :data' do
            data = {user_id: 5, appointment_id: 2}

            expect(persister).to receive(:read).with(data: JSON.dump(data)).and_return([{id: 1, run_at: 2}])

            queue.fetch_task(data: data)
         end

         it 'should complain if no task matches the given information' do
            identifier = {bogus: 66}

            [[], nil].each do |ret|
               allow(persister).to receive(:read).and_return(ret)

               expect do
                  queue.fetch_task(identifier)
               end.to raise_error(NoSuchTaskError, "no task found matching #{ identifier }")
            end
         end

         it 'should complain if multiple tasks match the given information' do
            identifier = {id: 'id'}
            (3..5).each do |n|
               tasks = Array.new(n) { |i| double("task#{ i }") }

               allow(persister).to receive(:read).and_return(tasks)

               msg = "too many (#{ n }) tasks match #{ identifier }. Found: #{ tasks }"

               expect do
                  queue.fetch_task(identifier)
               end.to raise_error(AmbiguousTaskFilterError, msg)
            end
         end
      end
   end
end
