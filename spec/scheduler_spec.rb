require 'spec_helper'

module Procrastinator
   describe Procrastinator::Scheduler do
      let(:test_task) {Test::Task::AllHooks}

      describe '#delay' do
         # api: Procrastinator.delay(run_at: Time.now + 10, queue: :email, SendInvitation.new(to: 'bob@example.com'))

         let(:persister) {Test::Persister.new}
         let(:config) do
            config = Config.new
            config.load_with do
               persister
            end
            config.define_queue(:test_queue, test_task)
            config
         end

         let(:scheduler) {Scheduler.new(config)}

         it 'should record a task on the given queue' do
            [:queue1, :queue2].each do |queue_name|
               config.define_queue(queue_name, test_task)

               expect(persister).to receive(:create_task).with(include(queue: queue_name))

               scheduler.delay(queue_name)
            end
         end

         it 'should record a task with given run_at' do
            run_stamp = double('runstamp')

            expect(persister).to receive(:create_task).with(include(run_at: run_stamp))

            scheduler.delay(:test_queue, run_at: double('time_object', to_i: run_stamp))
         end

         it 'should record a task with given expire_at' do
            expire_stamp = double('expirestamp')

            expect(persister).to receive(:create_task).with(include(expire_at: expire_stamp))

            scheduler.delay(:test_queue, expire_at: double('time_object', to_i: expire_stamp))
         end

         it 'should record a task with serialized task data' do
            data = double('some_data')

            # these are, at the moment, all of the arguments the dev can pass in
            expect(persister).to receive(:create_task).with(include(data: YAML.dump(data)))

            scheduler.delay(data: data)
         end

         it 'should default run_at to now' do
            now = Time.now

            Timecop.freeze(now) do
               expect(persister).to receive(:create_task).with(include(run_at: now.to_i))

               scheduler.delay()
            end
         end

         it 'should record initial_run_at and run_at to be equal' do
            time = Time.now

            expect(persister).to receive(:create_task).with(include(run_at: time.to_i, initial_run_at: time.to_i))

            scheduler.delay(run_at: time)
         end

         it 'should convert run_at, initial_run_at, expire_at to ints' do
            expect(persister).to receive(:create_task).with(include(run_at: 0, initial_run_at: 0, expire_at: 1))

            scheduler.delay(run_at:    double('time', to_i: 0),
                            expire_at: double('time', to_i: 1))
         end

         it 'should default expire_at to nil' do
            expect(persister).to receive(:create_task).with(include(expire_at: nil))

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

            expect {scheduler.delay(run_at: 0)}.to raise_error(ArgumentError, msg)

            # also test the negative
            expect {scheduler.delay(:queue1, run_at: 0)}.to_not raise_error
         end

         it 'should NOT require queue be provided if only one queue is defined' do
            config = Config.new
            config.load_with {persister}
            config.define_queue(:queue_name, test_task)

            scheduler = Scheduler.new(config)

            expect {scheduler.delay}.to_not raise_error
         end

         it 'should assume the queue name if only one queue is defined' do
            config = Config.new
            config.load_with {persister}
            config.define_queue(:some_queue, test_task)

            scheduler = Scheduler.new(config)

            expect(persister).to receive(:create_task).with(hash_including(queue: :some_queue))

            scheduler.delay
         end

         it 'should complain when the given queue is not registered' do
            config.define_queue(:another_queue, test_task)

            [:bogus, :other_bogus].each do |name|
               err = %[there is no :#{name} queue registered. Defined queues are: :test_queue, :another_queue]

               expect {scheduler.delay(name, run_at: 0)}.to raise_error(ArgumentError, err)
            end
         end
      end
   end
end