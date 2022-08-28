# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe Queue do
      let(:test_task) { Test::Task::AllHooks }
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

         context 'task class' do
            it 'should complain if task does not support #run' do
               task_class = Class.new do
                  # bad task
               end

               expect do
                  Queue.new(name: :test_queue, task_class: task_class)
               end.to raise_error(MalformedTaskError, "task #{ task_class } does not support #run method")
            end

            it 'should complain if task #run expects parameters' do
               klass = Procrastinator::Test::Task::Malformed::ArgRun

               err = "task #{ klass } cannot require parameters to its #run method"

               expect do
                  Queue.new(name: :test_queue, task_class: klass)
               end.to raise_error(MalformedTaskError, err)
            end

            it 'should complain if task does NOT accept 1 parameter to #success' do
               [Procrastinator::Test::Task::Malformed::NoArgSuccess,
                Procrastinator::Test::Task::Malformed::MultiArgSuccess].each do |klass|
                  err = "task #{ klass } must accept 1 parameter to its #success method"

                  expect do
                     Queue.new(name: :test_queue, task_class: klass)
                  end.to raise_error(MalformedTaskError, err)
               end
            end

            it 'should complain if task does NOT accept 1 parameter in #fail' do
               [Procrastinator::Test::Task::Malformed::NoArgFail,
                Procrastinator::Test::Task::Malformed::MultiArgFail].each do |klass|
                  err = "task #{ klass } must accept 1 parameter to its #fail method"

                  expect do
                     Queue.new(name: :test_queue, task_class: klass)
                  end.to raise_error(MalformedTaskError, err)
               end
            end

            it 'should complain if task does NOT accept 1 parameter in #final_fail' do
               [Procrastinator::Test::Task::Malformed::NoArgFinalFail,
                Procrastinator::Test::Task::Malformed::MultiArgFinalFail].each do |klass|
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
               def run
               end
            end
         end

         it 'should restore the stored scheduling metadata' do
            saved_metadata = {
                  id:             double('id'),
                  run_at:         double('run_at', to_i: 5),
                  initial_run_at: double('initial', to_i: 6),
                  expire_at:      double('expiry', to_i: 7),
            }

            queue = Queue.new(name: :email, task_class: test_task, store: fake_persister([saved_metadata]))

            _task, meta = queue.next_task

            expect(meta.id).to eq saved_metadata[:id]
            expect(meta.run_at).to eq 5
            expect(meta.initial_run_at).to eq 6
            expect(meta.expire_at).to eq 7
         end

         it 'should restore the stored failure metadata' do
            # need a nonzero run_at to not be ignored
            saved_metadata = {
                  run_at:       10,
                  attempts:     8,
                  last_error:   double('last error'),
                  last_fail_at: double('last fail at')
            }

            queue = Queue.new(name: :email, task_class: test_task, store: fake_persister([saved_metadata]))

            _task, meta = queue.next_task

            expect(meta.attempts).to eq saved_metadata[:attempts]
            expect(meta.last_error).to eq saved_metadata[:last_error]
            expect(meta.last_fail_at).to eq saved_metadata[:last_fail_at]
         end

         it 'should restore the stored task data' do
            data = {some_data: 5}
            # need a nonzero run_at to not be ignored
            saved_metadata = {
                  run_at: 10,
                  data:   JSON.dump(data)
            }

            queue = Queue.new(name: :email, task_class: test_task, store: fake_persister([saved_metadata]))

            _task, meta = queue.next_task

            expect(meta.data).to eq data
         end

         it 'should pass the TaskMetaData the queue definition' do
            queue = Queue.new(name: :email, task_class: task_class, store: fake_persister([{run_at: 1}]))

            _, metadata = queue.next_task
            expect(metadata.queue).to eq queue
         end

         it 'should ignore any unused or unknown fields' do
            task_data = {id:     1,
                         queue:  double('queue'),
                         run_at: double('run_at', to_i: 2),
                         bogus:  double('bogus')}

            queue = Queue.new(name: :email, task_class: task_class, store: fake_persister([task_data]))

            expect { queue.next_task }.to_not raise_error
         end

         it 'should filter tasks by the queue name' do
            persister = fake_persister([{id: 1, run_at: 1, queue: :reminder},
                                        {id: 2, run_at: 2, queue: :email},
                                        {id: 3, run_at: 3, queue: :welcome}])

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
               _, meta = queue.next_task
               expect(meta.id).to eq 2
            end
         end

         it 'should ignore tasks with nil run_at' do
            job1 = {id: 4, run_at: nil, initial_run_at: 0}
            job2 = {id: 5, run_at: 2, initial_run_at: 0}

            persister = double('disorganized persister',
                               read:   [job2, job1],
                               create: nil,
                               update: nil,
                               delete: nil)

            queue = Queue.new(name: :email, task_class: task_class, store: persister)

            _, meta = queue.next_task
            expect(meta.id).to eq 5
         end

         it 'should sort tasks by run_at' do
            job1 = {id: 1, run_at: 70, initial_run_at: 0}
            job2 = {id: 2, run_at: 60, initial_run_at: 0}
            job3 = {id: 3, run_at: 90, initial_run_at: 0}

            persister = double('disorganized persister',
                               read:   [job2, job1, job3],
                               create: nil,
                               update: nil,
                               delete: nil)

            queue = Queue.new(name: :email, task_class: task_class, store: persister)

            _task, meta = queue.next_task

            expect(meta.id).to eq 2
         end

         it 'should create a new task handler instance' do
            klass = Class.new do
               def run
               end
            end
            queue = Queue.new(name: :test_queue, task_class: klass, store: persister)

            task, _meta = queue.next_task

            expect(task).to be_a klass
         end

         it 'should provide no arguments to the constructor' do
            klass = Class.new do
               def run
               end
            end
            queue = Queue.new(name: :test_queue, task_class: klass, store: persister)

            expect(klass).to receive(:new).with(no_args)

            queue.next_task
         end

         context 'dependency injection' do
            let(:task_class) do
               Class.new do
                  include Procrastinator::Task

                  def run
                  end
               end
            end

            let(:task) { task_class.new }
            let(:meta) { TaskMetaData.new }
            let(:queue) { Queue.new(name: :test_queue, task_class: task_class, store: persister) }

            before(:each) do
               allow(task_class).to receive(:new).and_return(task)
            end

            it 'should provide the data packet to the new task instance if requested' do
               task_class.task_attr :data

               data      = 'data here'
               persister = fake_persister([{id: 2, run_at: 2, data: JSON.dump(data)}])

               queue = Queue.new(name: :test_queue, task_class: task_class, store: persister)

               expect(task).to receive(:data=).with(data)

               queue.next_task
            end

            it 'should provide the container to the new task instance if requested' do
               task_class.task_attr :container

               container = double('container')

               expect(task).to receive(:container=).with(container)

               queue.next_task(container: container)
            end

            it 'should provide the logger to the new task instance if requested' do
               task_class.task_attr :logger

               logger = Logger.new(StringIO.new)

               expect(task).to receive(:logger=).with(logger)

               queue.next_task(logger: logger)
            end

            it 'should provide the scheduler to the new task instance if requested' do
               task_class.task_attr :scheduler

               scheduler = double('scheduler')

               expect(task).to receive(:scheduler=).with(scheduler)

               queue.next_task(scheduler: scheduler)
            end
         end
      end

      describe 'create' do
         let(:task_with_data) do
            Class.new do
               attr_accessor :data

               def run
               end
            end
         end

         let(:task_without_data) do
            Class.new do
               def run
               end
            end
         end

         let(:required_args) { {run_at: nil, initial_run_at: nil, expire_at: nil, data: nil} }

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
               task #{ task_without_data } does not import :data. Add this in your class definition:
                     task_attr :data
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
   end
end
