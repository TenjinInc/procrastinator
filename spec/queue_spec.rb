require 'spec_helper'

module Procrastinator
   describe Queue do
      let(:test_task) {Test::Task::AllHooks}

      it 'should require a name' do
         expect {Procrastinator::Queue.new(task_class: nil)}.to raise_error(ArgumentError, 'missing keyword: name')
      end

      it 'should require a task_class' do
         expect {Procrastinator::Queue.new(name: '')}.to raise_error(ArgumentError, 'missing keyword: task_class')
      end

      it 'should convert the queue name to a symbol' do
         {
               space_before:  ' space_before',
               space_after:   'space_after ',
               space_inside:  'space inside',
               double_space:  'double  space',
               special_chars: 'special:[]!@#$%^&*()-=+<>\'",./?`~chars',

         }.each do |expected, input|
            queue = Procrastinator::Queue.new(name:       input,
                                              task_class: test_task)

            expect(queue.name).to eq expected
         end
      end

      it 'should require the name not be nil' do
         expect do
            Procrastinator::Queue.new(name: nil, task_class: test_task)
         end.to raise_error(ArgumentError, ':name may not be nil')
      end

      it 'should require the task class not be nil' do
         expect do
            Procrastinator::Queue.new(name: :test_name, task_class: nil)
         end.to raise_error(ArgumentError, ':task_class may not be nil')
      end

      it 'should require the task class respond to .new' do
         expect do
            Procrastinator::Queue.new(name:       :test_name,
                                      task_class: double('struct or whatever'))
         end.to raise_error(ArgumentError, 'Task class must be initializable')
      end

      it 'should accept a timeout' do
         (1..3).each do |t|
            queue = Procrastinator::Queue.new(name:       :queues,
                                              task_class: test_task,
                                              timeout:    t)

            expect(queue.timeout).to eq t
         end
      end

      it 'should provide default timeout' do
         queue = Procrastinator::Queue.new(name:       :queues,
                                           task_class: test_task)

         expect(queue.timeout).to eq Queue::DEFAULT_TIMEOUT
      end

      it 'should accept a max_attempts' do
         (1..3).each do |t|
            queue = Procrastinator::Queue.new(name:         :queues,
                                              task_class:   test_task,
                                              max_attempts: t)

            expect(queue.max_attempts).to eq t
         end
      end

      it 'should provide default max_attempts' do
         queue = Procrastinator::Queue.new(name:       :queues,
                                           task_class: test_task)

         expect(queue.max_attempts).to eq Queue::DEFAULT_MAX_ATTEMPTS
      end

      it 'should accept a update_period' do
         (1..3).each do |i|
            queue = Procrastinator::Queue.new(name:          :queues,
                                              task_class:    test_task,
                                              update_period: i)

            expect(queue.update_period).to eq i
         end
      end

      it 'should provide a default update_period' do
         queue = Procrastinator::Queue.new(name:       :queues,
                                           task_class: test_task)

         expect(queue.update_period).to eq Queue::DEFAULT_UPDATE_PERIOD
      end

      it 'should accept a max_tasks' do
         (1..3).each do |i|
            queue = Procrastinator::Queue.new(name:       :queues,
                                              task_class: test_task,
                                              max_tasks:  i)

            expect(queue.max_tasks).to eq i
         end
      end

      it 'should provide a default max_tasks' do
         queue = Procrastinator::Queue.new(name:       :queues,
                                           task_class: test_task)

         expect(queue.max_tasks).to eq Queue::DEFAULT_MAX_TASKS
      end
   end
end