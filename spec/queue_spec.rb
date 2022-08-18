# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe Queue do
      let(:test_task) { Test::Task::AllHooks }
      let(:persister) { fake_persister([]) }

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

         # queues should not
         it 'should freeze itself' do
            expect(basic_queue).to be_frozen
         end
      end
   end
end
