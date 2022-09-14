# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe TaskMetaData do
      let(:queue) { double('queue object', name: :test_queue, update: nil, max_attempts: nil) }

      describe '#inititalize' do
         let(:task) { double('task', run: nil) }

         it 'should store id' do
            id = double('id')

            task = TaskMetaData.new(id: id, queue: queue)

            expect(task.id).to eq id
         end

         it 'should store queue' do
            task = TaskMetaData.new(queue: queue)

            expect(task.queue).to eq queue
         end

         it 'should complain when queue is nil' do
            expect do
               TaskMetaData.new(queue: nil)
            end.to raise_error ArgumentError
         end

         it 'should deserialize data parameter' do
            task_data = {name: 'task-data', list: [1, 2, 3]}
            task_str  = JSON.dump(task_data)

            allow(JSON).to receive(:load).with(task_str).and_return(task_data)

            task = TaskMetaData.new(data: task_str, queue: queue)

            expect(task.data).to eq task_data
         end

         it 'should parse string time fields' do
            run_at         = '2022-01-01T01:01:01-01:00'
            initial_run_at = '2022-02-02T02:02:02-02:00'
            expire_at      = '2022-03-03T03:03:03-03:00'
            last_fail_at   = '2022-04-04T04:04:04-04:00'

            task = TaskMetaData.new(queue:          queue,
                                    run_at:         run_at,
                                    initial_run_at: initial_run_at,
                                    expire_at:      expire_at,
                                    last_fail_at:   last_fail_at)

            expect(task.run_at&.iso8601).to eq run_at
            expect(task.initial_run_at&.iso8601).to eq initial_run_at
            expect(task.expire_at&.iso8601).to eq expire_at
            expect(task.last_fail_at&.iso8601).to eq last_fail_at
         end

         it 'should parse integer time fields' do
            task = TaskMetaData.new(queue:          queue,
                                    run_at:         1,
                                    initial_run_at: 2,
                                    expire_at:      3,
                                    last_fail_at:   4)

            expect(task.run_at).to eq Time.at(1)
            expect(task.initial_run_at).to eq Time.at(2)
            expect(task.expire_at).to eq Time.at(3)
            expect(task.last_fail_at).to eq Time.at(4)
         end

         # Time. Tiiime time time time. Timetime? Time.
         it 'should parse Time time fields' do
            now = Time.now

            task = TaskMetaData.new(queue:          queue,
                                    run_at:         now,
                                    initial_run_at: now,
                                    expire_at:      now,
                                    last_fail_at:   now)

            expect(task.run_at).to eq now
            expect(task.initial_run_at).to eq now
            expect(task.expire_at).to eq now
            expect(task.last_fail_at).to eq now
         end

         it 'should parse to_time responding time fields' do
            now  = Time.now
            time = double('something timey wimey', to_time: now)

            task = TaskMetaData.new(queue:          queue,
                                    run_at:         time,
                                    initial_run_at: time,
                                    expire_at:      time,
                                    last_fail_at:   time)

            expect(task.run_at).to eq now
            expect(task.initial_run_at).to eq now
            expect(task.expire_at).to eq now
            expect(task.last_fail_at).to eq now
         end

         it 'should complain when a time is not understood' do
            [['some type', 'data'],
             ['other Type', 'bloop']].each do |klass, desc|
               expect do
                  TaskMetaData.new(queue:  queue,
                                   run_at: double('something', class: klass, to_s: desc))
               end.to raise_error ArgumentError, "Unknown data type: #{ klass } (#{ desc })"
            end
         end

         # nil run_at means that it should never be run. Used for final_fail marking
         it 'should NOT parse nil run_at' do
            task = TaskMetaData.new(run_at: nil, queue: queue)

            expect(task.run_at).to eq nil
         end

         # so that it doesn't insta-expire
         it 'should NOT parse nil expire_at' do
            task = TaskMetaData.new(expire_at: nil, queue: queue)

            expect(task.expire_at).to eq nil
         end

         it 'should default initial_run_at to run_at' do
            task = TaskMetaData.new(queue: queue, run_at: 0, initial_run_at: nil)

            expect(task.run_at).to eq Time.at 0
            expect(task.initial_run_at).to eq Time.at 0
         end

         it 'should default nil attempts to 0' do
            meta = TaskMetaData.new(attempts: nil, queue: queue)
            expect(meta.attempts).to be 0
         end

         it 'should convert attempts to integer' do
            meta = TaskMetaData.new(attempts: double('attempts', to_i: 5), queue: queue)
            expect(meta.attempts).to eq 5
         end
      end

      describe '#add_attempt' do
         let(:queue) { double('queue object', name: :test_queue, update: nil, max_attempts: 1) }

         it 'should increase the attempts' do
            meta = TaskMetaData.new(queue: queue, attempts: 0)
            meta.add_attempt
            expect(meta.attempts).to be 1
         end

         it 'should complain when so more attempts are available' do
            meta = TaskMetaData.new(queue: queue, attempts: 1)

            expect { meta.add_attempt }.to raise_error Task::AttemptsExhaustedError
         end
      end

      describe '#successful?' do
         it 'should return true when #run completes without error' do
            task = TaskMetaData.new(attempts: 1, queue: queue)

            expect(task.successful?).to be true
         end

         it 'should return false if a failure is recorded' do
            task = TaskMetaData.new(attempts: 1, last_fail_at: Time.now, last_error: 'asplode', queue: queue)

            expect(task.successful?).to be false
         end

         it 'should return false if the task is expired' do
            task = TaskMetaData.new(attempts: 1, expire_at: 0, queue: queue)

            expect(task.successful?).to be false
         end

         it 'should complain if the task has not been run yet' do
            task = TaskMetaData.new(attempts: 0, queue: queue)

            expect { task.successful? }.to raise_error(RuntimeError, 'you cannot check for success before running #work')
         end

         it 'should NOT complain if the task is expired' do
            task = TaskMetaData.new(attempts: 0, expire_at: 0, queue: queue)

            expect { task.successful? }.to_not raise_error
         end
      end

      describe '#expired?' do
         let(:now) { Time.now }

         it 'should return true when the expiry date has passed' do
            task = TaskMetaData.new(expire_at: now.to_i - 1, queue: queue)

            Timecop.freeze(now) do
               expect(task.expired?).to be true
            end
         end

         it 'should return false when the expiry date is not set' do
            task = TaskMetaData.new(expire_at: nil, queue: queue)

            Timecop.freeze(now) do
               expect(task.expired?).to be false
            end
         end

         it 'should return false when the expiry date has not passed' do
            task = TaskMetaData.new(expire_at: now.to_i + 1, queue: queue)

            Timecop.freeze(now) do
               expect(task.expired?).to be false
            end
         end
      end

      describe '#failure' do
         let(:fake_error) do
            err = StandardError.new('asplode')
            err.set_backtrace ['first line', 'second line']
            err
         end

         context 'normal failure' do
            let(:meta) { TaskMetaData.new(queue: queue, run_at: 0) }

            it 'should record the failure time' do
               now = Time.now

               Timecop.freeze(now) do
                  meta.failure(fake_error)
               end

               expect(meta.last_fail_at).to eq now
            end

            it 'should record the failure cause' do
               meta.failure(fake_error)

               recorded_err = meta.last_error
               expect(recorded_err).to start_with 'Task failed: '
               expect(recorded_err).to include fake_error.message # error message
               expect(recorded_err).to include 'first line' # backtrace lines
               expect(recorded_err).to include 'second line'
            end

            it 'should reschedule' do
               meta.failure(fake_error)

               expect(meta.run_at.to_i).to be > 0
            end

            it 'should return :fail' do
               expect(meta.failure(fake_error)).to be :fail
            end
         end

         context 'final failure' do
            let(:queue) { Queue.new(name: :final_queue, task_class: Test::Task::Fail, max_attempts: 1) }
            let(:meta) { TaskMetaData.new(queue: queue, run_at: 0, expire_at: 0, attempts: 0) }

            before(:each) do
               allow(meta).to receive(:retryable?).and_return false
            end

            it 'should NOT reschedule' do
               meta.failure(fake_error)

               expect(meta.run_at.to_i).to eq 0
            end

            it 'should set run_at to nil' do
               meta.failure(fake_error)

               expect(meta.run_at).to be_nil
            end

            it 'should return :final_fail' do
               expect(meta.failure(fake_error)).to be :final_fail
            end
         end
      end

      describe '#retryable?' do
         let(:queue) { Queue.new(name: :final_queue, task_class: Test::Task::Fail, max_attempts: 1) }

         it 'should return true when not expired and attempts remain' do
            meta = TaskMetaData.new(queue: queue, run_at: 0, expire_at: nil, attempts: 0)
            expect(meta.retryable?).to be true
         end

         it 'should return false when expired' do
            meta = TaskMetaData.new(queue: queue, run_at: 0, expire_at: Time.now, attempts: 0)
            expect(meta.retryable?).to be false
         end

         it 'should return false when out of attempts' do
            meta = TaskMetaData.new(queue: queue, run_at: 0, expire_at: nil, attempts: 1)
            expect(meta.retryable?).to be false
         end
      end

      describe '#attempts_left?' do
         let(:queue) do
            Procrastinator::Queue.new(name:         :queue,
                                      task_class:   Test::Task::Fail,
                                      max_attempts: 3, store: fake_persister)
         end

         it 'should be true if under the limit' do
            expect(TaskMetaData.new(attempts: 1, queue: queue).attempts_left?).to be true
            expect(TaskMetaData.new(attempts: 2, queue: queue).attempts_left?).to be true
         end

         it 'should be false if at or above the limit' do
            expect(TaskMetaData.new(attempts: 3, queue: queue).attempts_left?).to be false
            expect(TaskMetaData.new(attempts: 4, queue: queue).attempts_left?).to be false
         end

         it 'should always be false if nil max_attempts is given' do
            queue = Procrastinator::Queue.new(name:         :queue,
                                              task_class:   Test::Task::Fail,
                                              max_attempts: nil)

            (1..100).each do |i|
               expect(TaskMetaData.new(attempts: i, queue: queue).attempts_left?).to be true
            end
         end
      end

      describe '#runnable?' do
         it 'should return true if the run_at is in the past' do
            task = TaskMetaData.new(run_at: 0, queue: queue)

            expect(task.runnable?).to be true
         end

         it 'should return false if run_at is in the future' do
            now = Time.now

            task = TaskMetaData.new(run_at: now + 1, queue: queue)

            Timecop.freeze(now) do
               expect(task.runnable?).to be false
            end
         end

         it 'should return false if it is marked as final failed' do
            task = TaskMetaData.new(run_at: nil, queue: queue)

            expect(task.runnable?).to be false
         end
      end

      describe '#reschedule' do
         # TODO: reschedule based on a Queue settings proc calculator
         it 'should reschedule it exponentially when unspecified' do
            now  = Time.now
            task = TaskMetaData.new(queue: queue, run_at: now)
            task.reschedule
            expect(task.run_at).to eq now + 30

            task = TaskMetaData.new(queue: queue, run_at: now, attempts: 1)
            task.reschedule
            expect(task.run_at).to eq now + 31

            task = TaskMetaData.new(queue: queue, run_at: now, attempts: 4)
            task.reschedule
            expect(task.run_at).to eq now + 286
         end

         it 'should reschedule it to the given time' do
            now  = Time.now
            task = TaskMetaData.new(queue: queue, run_at: now, initial_run_at: now)

            new_time = Time.at(0)
            task.reschedule(run_at: new_time)

            expect(task.run_at).to eq new_time
            expect(task.initial_run_at).to eq new_time
         end

         it 'should complain if the given run_at would be after original expire_at' do
            run_at    = Time.now + 1
            expire_at = Time.now
            task      = TaskMetaData.new(queue: queue, expire_at: expire_at)

            expect do
               task.reschedule(run_at: run_at)
            end.to raise_error ArgumentError,
                               "new run_at (#{ run_at }) is later than existing expire_at (#{ expire_at })"
         end

         it 'should complain if the new run_at would be after new expire_at' do
            run_at    = Time.now + 1
            expire_at = Time.now
            task      = TaskMetaData.new(queue: queue)

            expect do
               task.reschedule(run_at: run_at, expire_at: expire_at)
            end.to raise_error ArgumentError, "new run_at (#{ run_at }) is later than new expire_at (#{ expire_at })"
         end

         it 'should reset the initial run and attempts and failures when run_at specified' do
            task = TaskMetaData.new(queue:          queue,
                                    initial_run_at: 0,
                                    attempts:       5,
                                    last_fail_at:   Time.at(1000),
                                    last_error:     'some error')

            now = Time.now
            task.reschedule(run_at: now)

            expect(task.attempts).to eq 0
            expect(task.last_error).to be_nil
            expect(task.last_fail_at).to be_nil
         end

         it 'should NOT reset the attempts and failures when run_at unspecified' do
            last_fail = Time.at(1000)
            task      = TaskMetaData.new(queue:        queue,
                                         attempts:     5,
                                         last_fail_at: last_fail,
                                         last_error:   'some error')

            task.reschedule

            expect(task.attempts).to eq 5
            expect(task.last_error).to eq 'some error'
            expect(task.last_fail_at).to eq last_fail
         end

         it 'should NOT update run_at and initial_run_at if run_at is not provided' do
            task = TaskMetaData.new(queue: queue, run_at: 0)

            task.reschedule(expire_at: Time.now)

            expect(task.run_at).to eq Time.at(0)
            expect(task.initial_run_at).to eq Time.at(0)
         end

         it 'should update expire_at to the given time' do
            expire_at = Time.now + 10

            task = TaskMetaData.new(queue: queue, expire_at: 0)

            task.reschedule(expire_at: expire_at)

            expect(task.expire_at).to eq expire_at
         end

         it 'should NOT update expire_at when only run_at is provided' do
            expire = Time.now + 1000
            task   = TaskMetaData.new(queue: queue, expire_at: expire)

            task.reschedule(run_at: Time.now)

            expect(task.expire_at).to eq expire
         end
      end

      describe '#to_h' do
         let(:queue) { double('queue', name: :some_queue) }

         it 'should return the properties as a hash' do
            task = TaskMetaData.new(queue: queue)

            expect(task.to_h).to be_a Hash
         end

         # converting to string avoids interpretation by some persistence libraries (eg. ROM MySQL auto column name)
         it 'should include the queue name as string' do
            task = TaskMetaData.new(queue: double('queue', name: :reminders))

            expect(task.to_h).to include(queue: 'reminders')
         end

         it 'should include the serialized data' do
            data_str = JSON.dump('some data')
            task     = TaskMetaData.new(queue: queue, data: data_str)

            expect(task.to_h).to include(data: data_str)
         end

         it 'should include the id' do
            id = double('id')

            task = TaskMetaData.new(id: id, queue: queue)

            expect(task.to_h).to include(id: id)
         end

         it 'should include the run information as Time objects' do
            run_at         = '2022-03-04T00:01:20-06:00'
            initial_run_at = '2022-03-04T00:01:20-06:00'
            expire_at      = '2022-03-04T00:01:20-06:00'

            task = TaskMetaData.new(queue:          queue,
                                    initial_run_at: initial_run_at,
                                    run_at:         run_at,
                                    expire_at:      expire_at)

            expect(task.to_h).to include(initial_run_at: Time.parse(initial_run_at),
                                         run_at:         Time.parse(run_at),
                                         expire_at:      Time.parse(expire_at))
         end

         it 'should include the attempts and failure information' do
            attempts   = 37
            fail_time  = '2022-03-04T00:01:20-06:00'
            last_error = double('last_error')

            task = TaskMetaData.new(queue: queue, attempts: attempts, last_error: last_error, last_fail_at: fail_time)

            expect(task.to_h).to include(attempts:     attempts,
                                         last_fail_at: Time.parse(fail_time),
                                         last_error:   last_error)
         end
      end
   end
end
