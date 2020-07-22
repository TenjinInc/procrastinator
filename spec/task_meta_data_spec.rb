# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe TaskMetaData do
      describe '#inititalize' do
         let(:task) { double('task', run: nil) }

         it 'should store id' do
            id = double('id')

            task = TaskMetaData.new(id: id)

            expect(task.id).to eq id
         end

         it 'should deserialize data parameter' do
            task_data = {name: 'task-data', list: [1, 2, 3]}
            task_yml  = YAML.dump(task_data)

            allow(YAML).to receive(:load).with(task_yml).and_return(task_data)

            task = TaskMetaData.new(data: task_yml)

            expect(task.data).to eq task_data
         end

         it 'should convert non-nil run_at, initial_run at, and expire_at to ints' do
            now = Time.now

            task = TaskMetaData.new(run_at: now, initial_run_at: now, expire_at: now)

            expect(task.run_at).to eq now.to_i
            expect(task.initial_run_at).to eq now.to_i
            expect(task.expire_at).to eq now.to_i
         end

         # nil run_at means that it should never be run. Used for final_fail marking
         it 'should NOT convert nil run_at to int' do
            task = TaskMetaData.new(run_at: nil)

            expect(task.run_at).to eq nil
         end

         # so that it doesn't insta-expire
         it 'should NOT convert nil expire_at to int' do
            task = TaskMetaData.new(expire_at: nil)

            expect(task.expire_at).to eq nil
         end

         it 'should default nil attempts to 0' do
            task = TaskMetaData.new(attempts: nil)
            expect(task.attempts).to be 0
         end
      end

      describe '#successful?' do
         it 'should return true when #run completes without error' do
            task = TaskMetaData.new(attempts: 1)

            expect(task.successful?).to be true
         end

         it 'should return false if a failure is recorded' do
            task = TaskMetaData.new(attempts: 1, last_fail_at: Time.now, last_error: 'derp')

            expect(task.successful?).to be false
         end

         it 'should return false if the task is expired' do
            task = TaskMetaData.new(attempts: 1, expire_at: 0)

            expect(task.successful?).to be false
         end

         it 'should complain if the task has not been run yet' do
            task = TaskMetaData.new(attempts: 0)

            expect { task.successful? }.to raise_error(RuntimeError, 'you cannot check for success before running #work')
         end

         it 'should NOT complain if the task is expired' do
            task = TaskMetaData.new(attempts: 0, expire_at: 0)

            expect { task.successful? }.to_not raise_error
         end
      end

      describe '#expired?' do
         let(:now) { Time.now }

         it 'should return true when the expiry date has passed' do
            task = TaskMetaData.new(expire_at: now.to_i - 1)

            Timecop.freeze(now) do
               expect(task.expired?).to be true
            end
         end

         it 'should return false when the expiry date is not set' do
            task = TaskMetaData.new(expire_at: nil)

            Timecop.freeze(now) do
               expect(task.expired?).to be false
            end
         end

         it 'should return false when the expiry date has not passed' do
            task = TaskMetaData.new(expire_at: now.to_i)

            Timecop.freeze(now) do
               expect(task.expired?).to be false
            end
         end
      end

      describe '#too_many_fails?' do
         let(:queue) do
            Procrastinator::Queue.new(name:         :queue,
                                      task_class:   Test::Task::Fail,
                                      max_attempts: 3)
         end

         it 'should be true if under the limit' do
            expect(TaskMetaData.new(attempts: 1).too_many_fails?(queue)).to be false
            expect(TaskMetaData.new(attempts: 2).too_many_fails?(queue)).to be false
         end

         it 'should be false if at or above the limit' do
            expect(TaskMetaData.new(attempts: 3).too_many_fails?(queue)).to be true
            expect(TaskMetaData.new(attempts: 4).too_many_fails?(queue)).to be true
         end

         it 'should always be false if nil max_attempts is given' do
            queue = Procrastinator::Queue.new(name:         :queue,
                                              task_class:   Test::Task::Fail,
                                              max_attempts: nil)

            (1..100).each do |i|
               expect(TaskMetaData.new(attempts: i).too_many_fails?(queue)).to be false
            end
         end
      end

      describe '#runnable?' do
         it 'should return true if it is after the run_at' do
            task = TaskMetaData.new(run_at: 0)

            expect(task.runnable?).to be true
         end

         it 'should return false if it is before the run_at' do
            now = Time.now

            task = TaskMetaData.new(run_at: now + 1)

            Timecop.freeze(now) do
               expect(task.runnable?).to be false
            end
         end

         it 'should return false if it is marked as final failed' do
            task = TaskMetaData.new(run_at: nil)

            expect(task.runnable?).to be false
         end
      end

      describe '#init_task' do
         it 'should pass no parameters if no data' do
            meta       = TaskMetaData.new(data: nil)
            task_class = double('klass')

            expect(task_class).to receive(:new).with(no_args)

            queue = double('queue', task_class: task_class)

            meta.init_task(queue)
         end

         it 'should pass in the data to the task initialization if data' do
            data = 'task data'
            allow(YAML).to receive(:load).and_return(data)

            meta       = TaskMetaData.new(data: YAML.dump(data))
            task_class = double('klass')

            expect(task_class).to receive(:new).with(data)

            queue = double('queue', task_class: task_class)

            meta.init_task(queue)
         end
      end

      describe '#to_h' do
         it 'should return the properties as a hash' do
            basics = {
                  id:           double('id'),
                  attempts:     double('attempts'),
                  last_fail_at: double('last_fail_at'),
                  last_error:   double('last_error'),
                  data:         YAML.dump('some data')
            }

            run_at         = double('run_at', to_i: double('run_at_i'))
            initial_run_at = double('initial_run_at', to_i: double('initial_run_at_i'))
            expire_at      = double('expire_at', to_i: double('expire_at_i'))

            task = TaskMetaData.new(basics.merge(initial_run_at: initial_run_at,
                                                 run_at:         run_at,
                                                 expire_at:      expire_at))

            expect(task.to_h).to eq(basics.merge(initial_run_at: initial_run_at.to_i,
                                                 run_at:         run_at.to_i,
                                                 expire_at:      expire_at.to_i))
         end
      end
   end
end
