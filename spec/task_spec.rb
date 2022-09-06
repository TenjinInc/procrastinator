# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe Task do
      describe '#run' do
         let(:queue) { double('test queue', name: :test_queue) }
         let(:meta) { TaskMetaData.new(queue: queue) }
         let(:handler) { Test::Task::AllHooks.new }

         it 'should increase number of attempts when #run is called' do
            task = Task.new(meta, handler)

            (1..3).each do |i|
               task.run
               expect(task.attempts).to eq i
            end
         end

         it 'should call the handler run' do
            task = Task.new(meta, handler)

            expect(handler).to receive(:run)

            task.run
         end

         it 'should blank the error message' do
            meta = TaskMetaData.new(last_error: 'asplode',
                                    queue:      queue)
            task = Task.new(meta, double('task', run: nil))

            task.run

            expect(meta.last_error).to be nil
         end

         it 'should blank the error time' do
            meta = TaskMetaData.new(last_fail_at: Time.now,
                                    queue:        queue)
            task = Task.new(meta, double('task', run: nil))

            task.run

            expect(meta.last_fail_at).to be nil
         end

         it 'should complain when the task is expired' do
            now  = Time.now - 1
            meta = TaskMetaData.new(queue: queue, expire_at: now)
            task = Task.new(meta, handler)

            expect { task.run }.to raise_error Task::ExpiredError, "task is over its expiry time of #{ now.iso8601 }"
         end

         context 'handler failure' do
            it 'should increase number of attempts when #run fails' do
               task = Task.new(meta, handler)
               allow(handler).to receive(:run).and_raise 'asplode'

               (1..3).each do |i|
                  expect { task.run }.to raise_error RuntimeError, 'asplode'
                  expect(task.attempts).to eq i
               end
            end

            it 'should NOT clear fails when #run fails' do
               now  = Time.now
               meta = TaskMetaData.new(queue:        queue,
                                       last_error:   'cocoon',
                                       last_fail_at: now)
               task = Task.new(meta, handler)

               allow(handler).to receive(:run).and_raise 'asplode'

               expect { task.run }.to raise_error RuntimeError, 'asplode'

               expect(meta.last_error).to eq 'cocoon'
               expect(meta.last_fail_at).to eq now
            end
         end

      end

      describe '#to_s' do
         it 'should include the queue name' do
            [:email, :reminder].each do |name|
               queue = double('test queue', name: name)
               meta  = TaskMetaData.new(queue: queue)
               task  = Task.new(meta, double('task', run: nil))

               expect(task.to_s).to include(name.to_s)
            end
         end

         it 'should include the queue id number' do
            queue = double('test queue', name: :some_queue)
            (1..3).each do |i|
               meta = TaskMetaData.new(queue: queue, id: i)
               task = Task.new(meta, double('task', run: nil))

               expect(task.to_s).to include("##{ i }")
            end
         end

         it 'should include the data packet' do
            queue = double('test queue', name: :some_queue)
            data  = JSON.dump({email: 'judge@example.com'})
            meta  = TaskMetaData.new(queue: queue, data: data)
            task  = Task.new(meta, double('task', run: nil))

            expect(task.to_s).to include(data)
         end
      end
   end
end

