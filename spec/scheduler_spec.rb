require 'spec_helper'

module Procrastinator
   describe Procrastinator::Scheduler do
      let(:test_task) { Test::Task::AllHooks }

      describe '#delay' do
         # api: Procrastinator.delay(run_at: Time.now + 10, queue: :email, SendInvitation.new(to: 'bob@example.com'))

         let(:persister) { Test::Persister.new }
         let(:config) do
            config = Config.new
            config.load_with(persister)
            config.define_queue(:test_queue, test_task)
            config
         end

         let(:scheduler) { Scheduler.new(config) }

         it 'should record a task on the given queue' do
            [:queue1, :queue2].each do |queue_name|
               config.define_queue(queue_name, test_task)

               expect(persister).to receive(:create).with(include(queue: queue_name))

               scheduler.delay(queue_name)
            end
         end

         it 'should record a task with given run_at' do
            run_stamp = double('runstamp')

            expect(persister).to receive(:create).with(include(run_at: run_stamp))

            scheduler.delay(:test_queue, run_at: double('time_object', to_i: run_stamp))
         end

         it 'should record a task with given expire_at' do
            expire_stamp = double('expirestamp')

            expect(persister).to receive(:create).with(include(expire_at: expire_stamp))

            scheduler.delay(:test_queue, expire_at: double('time_object', to_i: expire_stamp))
         end

         it 'should record a task with serialized task data' do
            task_with_data = Class.new do
               include Task

               task_attr :data

               def run
               end
            end

            config.define_queue(:data_queue, task_with_data)

            data = double('some_data')

            # these are, at the moment, all of the arguments the dev can pass in
            expect(persister).to receive(:create).with(include(data: YAML.dump(data)))

            scheduler.delay(:data_queue, data: data)
         end

         it 'should default run_at to now' do
            now = Time.now

            Timecop.freeze(now) do
               expect(persister).to receive(:create).with(include(run_at: now.to_i))

               scheduler.delay()
            end
         end

         it 'should record initial_run_at and run_at to be equal' do
            time = Time.now

            expect(persister).to receive(:create).with(include(run_at: time.to_i, initial_run_at: time.to_i))

            scheduler.delay(run_at: time)
         end

         it 'should convert run_at, initial_run_at, expire_at to ints' do
            expect(persister).to receive(:create).with(include(run_at: 0, initial_run_at: 0, expire_at: 1))

            scheduler.delay(run_at:    double('time', to_i: 0),
                            expire_at: double('time', to_i: 1))
         end

         it 'should default expire_at to nil' do
            expect(persister).to receive(:create).with(include(expire_at: nil))

            scheduler.delay
         end

         it 'should NOT complain about well-formed hooks' do
            [:success, :fail, :final_fail].each do |method|
               task = test_task.new

               allow(task).to receive(method)

               expect do
                  scheduler.delay
               end.to_not raise_error
            end
         end

         it 'should require queue be provided if there is more than one queue defined' do
            config.define_queue(:queue1, test_task)
            config.define_queue(:queue2, test_task)

            msg = "queue must be specified when more than one is registered. Defined queues are: :test_queue, :queue1, :queue2"

            "queue must be specified when more than one is registered. Defined queues are: :test_queue, :queue1, :queue2"
            "queue must be specified when more than one is registered. Defined queues are: test_queue, queue1, queue2"

            expect { scheduler.delay(run_at: 0) }.to raise_error(ArgumentError, msg)

            # also test the negative
            expect { scheduler.delay(:queue1, run_at: 0) }.to_not raise_error
         end

         it 'should NOT require queue be provided if only one queue is defined' do
            config = Config.new
            config.load_with(persister)
            config.define_queue(:queue_name, test_task)

            scheduler = Scheduler.new(config)

            expect { scheduler.delay }.to_not raise_error
         end

         it 'should assume the queue name if only one queue is defined' do
            config = Config.new
            config.load_with(persister)
            config.define_queue(:some_queue, test_task)

            scheduler = Scheduler.new(config)

            expect(persister).to receive(:create).with(hash_including(queue: :some_queue))

            scheduler.delay
         end

         it 'should complain when the given queue is not registered' do
            config.define_queue(:another_queue, test_task)

            [:bogus, :other_bogus].each do |name|
               err = %[there is no :#{name} queue registered. Defined queues are: :test_queue, :another_queue]

               expect { scheduler.delay(name) }.to raise_error(ArgumentError, err)
            end
         end

         it 'should complain if they provide NO :data in #delay, but the task expects it' do
            test_task = Class.new do
               include Procrastinator::Task

               task_attr :data

               def run
               end
            end

            config.define_queue(:data_queue, test_task)

            err = %[task #{test_task} expects to receive :data. Provide :data to #delay.]

            expect { scheduler.delay(:data_queue) }.to raise_error(ArgumentError, err)
         end

         it 'should complain if they provide :data in #delay, but the task does NOT import it' do
            test_task = Class.new do
               include Procrastinator::Task

               def run
               end
            end

            config.define_queue(:data_queue, test_task)

            err = <<~ERROR
               task #{test_task} does not import :data. Add this in your class definition:
                     import_test_data :data
            ERROR

            expect { scheduler.delay(:data_queue, data: 'some data') }.to raise_error(ArgumentError, err)
         end
      end

      describe '#reschedule' do
         let(:persister) { Test::Persister.new }
         let(:config) do
            config = Config.new
            config.load_with(persister)
            config.define_queue(:test_queue, test_task)
            config
         end
         let(:scheduler) { Scheduler.new(config) }

         it 'should create a proxy for the given search parameters' do
            queue      = double('q')
            identifier = double('i')

            expect(Scheduler::UpdateProxy).to receive(:new)
                                                    .with(config,
                                                          queue_name: queue,
                                                          identifier: identifier)

            scheduler.reschedule(queue, identifier)
         end

         it 'should return the created proxy' do
            proxy = double('proxy')

            allow(Scheduler::UpdateProxy).to receive(:new).and_return(proxy)

            expect(scheduler.reschedule(:test_queue, double('id'))).to be proxy
         end
      end

      describe '#cancel' do
         let(:persister) { Test::Persister.new }
         let(:config) do
            config = Config.new
            config.load_with(persister)
            config.define_queue(:greeting, test_task)
            config.define_queue(:reminder, test_task)
            config
         end
         let(:scheduler) { Scheduler.new(config) }

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
               attrs[:queue] == :reminder ? [tasks.first] : [tasks.last]
            end

            # first search
            expect(persister).to receive(:delete).with(2)
            scheduler.cancel(:greeting, data: {user_id: 5})

            #second search
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
               end.to raise_error(RuntimeError, "no task matches search: #{identifier}")
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
               end.to raise_error(RuntimeError, "multiple tasks match search: #{identifier}")
            end
         end
      end
   end

   describe Scheduler::UpdateProxy do

      let(:test_task) { Test::Task::AllHooks }
      let(:persister) { Test::Persister.new }
      let(:config) do
         config = Config.new
         config.load_with(persister)
         config.define_queue(:test_queue, test_task)
         config
      end
      let(:identifier) { {id: 'id'} }
      let(:update_proxy) { Scheduler::UpdateProxy.new(config,
                                                      queue_name: :test_queue,
                                                      identifier: identifier) }

      describe '#to' do
         before(:each) do
            allow(persister).to receive(:read).and_return([{id: 5}])
         end

         it 'should find the task matching the given information' do
            [{id: 5}, {data: {user_id: 5, appointment_id: 2}}].each do |identifier|
               update_proxy = Scheduler::UpdateProxy.new(config, identifier: identifier, queue_name: :test_queue)

               expect(persister).to receive(:read).with(identifier).and_return([double('task', '[]': 6)])

               update_proxy.to(run_at: 0)
            end
         end

         it 'should find the task matching the given serialized :data' do
            data = {user_id: 5, appointment_id: 2}

            update_proxy = Scheduler::UpdateProxy.new(config, identifier: {data: data}, queue_name: :test_queue)

            expect(persister).to receive(:read).with(data: YAML.dump(data)).and_return([double('task', '[]': 6)])

            update_proxy.to(run_at: 0)
         end

         it 'should complain if no task matches the given information' do
            identifier = {bogus: 66}

            update_proxy = Scheduler::UpdateProxy.new(config,
                                                      queue_name: :test_queue,
                                                      identifier: identifier)

            [[], nil].each do |ret|
               allow(persister).to receive(:read).and_return(ret)

               expect do
                  update_proxy.to(run_at: 0)
               end.to raise_error(RuntimeError, "no task found matching #{identifier}")
            end
         end

         it 'should complain if multiple tasks match the given information' do
            (3..5).each do |n|
               tasks = Array.new(n) { |i| double("task#{i}") }

               allow(persister).to receive(:read).and_return(tasks)

               expect do
                  update_proxy.to(run_at: 0)
               end.to raise_error(RuntimeError, "too many (#{n}) tasks match #{identifier}. Found: #{tasks}")
            end
         end

         it 'should complain if the given run_at would be after given expire_at' do
            time      = Time.now
            expire_at = Time.at 0

            expect do
               update_proxy.to(run_at: time, expire_at: expire_at)
            end.to raise_error(RuntimeError, "given run_at (#{time}) is later than given expire_at (#{expire_at})")
         end

         it 'should complain if the given run_at would be after original expire_at' do
            time      = Time.now
            expire_at = Time.at 0

            allow(persister).to receive(:read).and_return([TaskMetaData.new(expire_at: expire_at.to_i).to_h])

            expect do
               update_proxy.to(run_at: time)
            end.to raise_error(RuntimeError,
                               "given run_at (#{time}) is later than saved expire_at (#{expire_at.to_i})")
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
end