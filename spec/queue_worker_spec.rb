require 'spec_helper'

module Procrastinator
   describe QueueWorker do
      let(:persister) { loader = double('loader', read_tasks: [], update_task: nil, delete_task: nil) }

      describe '#initialize' do
         it 'should require a name' do
            expect { QueueWorker.new }.to raise_error(ArgumentError)
         end

         it 'should store name as symbol' do
            [:email, :cleanup, 'a name'].each do |name|
               queue = QueueWorker.new(name: name, persister: persister)

               expect(queue.name).to eq name.to_s.gsub(/\s/, '_').to_sym
            end
         end

         it 'should require the name not be nil' do
            expect do
               QueueWorker.new(name: nil, persister: persister)
            end.to raise_error(ArgumentError, 'Queue name may not be nil')
         end

         it 'should require a persister' do
            expect do
               QueueWorker.new(name: :queue)
            end.to raise_error(ArgumentError, 'missing keyword: persister')
         end

         it 'should require the persister not be nil' do
            expect do
               QueueWorker.new(name: :queue, persister: nil)
            end.to raise_error(ArgumentError, 'Persister may not be nil')
         end

         it 'should require the persister respond to #read_tasks' do
            expect do
               QueueWorker.new(name: :queue, persister: double('broken persister', delete_task: nil, update_task: nil))
            end.to raise_error(MalformedTaskPersisterError, 'The supplied IO object must respond to #read_tasks')
         end

         it 'should require the persister respond to #update_task' do
            expect do
               QueueWorker.new(name: :queue, persister: double('broken persister', read_tasks: []))
            end.to raise_error(MalformedTaskPersisterError, 'The supplied IO object must respond to #update_task')
         end

         it 'should require the persister respond to #delete_task' do
            expect do
               QueueWorker.new(name: :queue, persister: double('broken persister', read_tasks: [], update_task: nil))
            end.to raise_error(MalformedTaskPersisterError, 'The supplied IO object must respond to #delete_task')
         end

         it 'should accept a timeout' do
            (1..3).each do |t|
               queue = QueueWorker.new(name: :queue, persister: persister, timeout: t)

               expect(queue.timeout).to eq t
            end
         end

         it 'should provide default timeout' do
            queue = QueueWorker.new(name: :queue, persister: persister)

            expect(queue.timeout).to eq QueueWorker::DEFAULT_TIMEOUT
         end

         it 'should accept a max_attempts' do
            (1..3).each do |t|
               queue = QueueWorker.new(name: :queue, persister: persister, max_attempts: t)

               expect(queue.max_attempts).to eq t
            end
         end

         it 'should provide default max_attempts' do
            queue = QueueWorker.new(name: :queue, persister: persister)

            expect(queue.max_attempts).to eq QueueWorker::DEFAULT_MAX_ATTEMPTS
         end

         it 'should accept a update_period' do
            (1..3).each do |i|
               queue = QueueWorker.new(name: :queue, persister: persister, update_period: i)

               expect(queue.update_period).to eq i
            end
         end

         it 'should provide a default update_period' do
            queue = QueueWorker.new(name: :queue, persister: persister)

            expect(queue.update_period).to eq QueueWorker::DEFAULT_UPDATE_PERIOD
         end

         it 'should accept a max_tasks' do
            (1..3).each do |i|
               queue = QueueWorker.new(name: :queue, persister: persister, max_tasks: i)

               expect(queue.max_tasks).to eq i
            end
         end

         it 'should provide a default max_tasks' do
            queue = QueueWorker.new(name: :queue, persister: persister)

            expect(queue.max_tasks).to eq QueueWorker::DEFAULT_MAX_TASKS
         end
      end

      describe '#work' do
         context 'loading tasks' do
            def stub_loop(object, count = 1)
               allow(object).to receive(:loop) do |&block|
                  count.times { block.call }
               end
            end

            it 'should wait for update_period' do
               [0.01, 0.02].each do |period|
                  worker = QueueWorker.new(name: :queue, persister: persister, update_period: period)

                  stub_loop(worker)

                  expect(worker).to receive(:sleep).with(period)

                  worker.work
               end
            end

            it 'should pass the given queue to its persister' do
               [:email, :cleanup].each do |queue|
                  worker = QueueWorker.new(name: queue, persister: persister, update_period: 0.01)
                  stub_loop(worker)

                  expect(persister).to receive(:read_tasks).with(queue)

                  worker.work
               end
            end

            it 'should sort tasks by run_at' do
               job1 = double('job1', run_at: 1)
               job2 = double('job2', run_at: 2)
               job3 = double('job3', run_at: 3)

               persister = double('disorganized persister', read_tasks: [job2, job3, job1], update_task: nil, delete_task: nil)
               worker    = QueueWorker.new(name: :queue, persister: persister, update_period: 0.01)
               stub_loop(worker)

               expect(job1).to receive(:run).ordered
               expect(job2).to receive(:run).ordered
               expect(job3).to receive(:run).ordered

               worker.work
            end

            it 'should reload tasks every cycle' do
               job1 = double('job1', run_at: 1)
               job2 = double('job2', run_at: 1)

               allow(job1).to receive(:run) do
                  Timecop.travel(4)
               end
               allow(job2).to receive(:run) do
                  Timecop.travel(6)
               end

               allow(persister).to receive(:read_tasks).and_return([job1], [job2])

               start_time = Time.now

               Timecop.freeze(start_time) do
                  worker = QueueWorker.new(name: :queue, persister: persister, update_period: 0.00)
                  stub_loop(worker, 2)

                  worker.work

                  expect(Time.now.to_i).to eq start_time.to_i + 10
               end
            end

            it 'should #work a TaskWorker for each ready task'# do
               # job1 = double('job1', run_at: 1, run: nil)
               # job2 = double('job2', run_at: 1, run: nil)
               #
               # persister = double('disorganized persister', update_task: nil, delete_task: nil)
               # allow(persister).to receive(:read_tasks).and_return([job1, job2])
               #
               # worker = QueueWorker.new(name: :queue, persister: persister, update_period: 0)
               # stub_loop(worker)
               #
               # worker.work
            #end

            it 'should not start more TaskWorkers than max_tasks'
            #set max_tasks to 1, give 2 ready jobs.

            it 'should not start a TaskWorker any unready tasks'
         end

         context 'TaskWorker succeeds' do
            it 'should delete the task'
         end

         context 'TaskWorker failed' do
            it 'should reschedule for the future'
            it 'should reschedule on an increasing basis'
         end

         context 'TaskWorker failed for the last time' do
            # to do: promote captain Piett to admiral


            it 'should mark the task as permanently failed' # maybe by blanking run_at?
         end
      end

      describe '#stop' do
         it 'should stop looping' # do
         #    worker = QueueWorker.new(name: :queue, persister: persister, update_period: 0.00)
         #
         #    thread = Thread.new do
         #       worker.work # this infiniloops until told to stop
         #       Thread.exit
         #    end
         #
         #    sleep(0.5)
         #
         #    worker.stop
         #
         #    expect(thread.status).to be false
         #
         #    if thread.status != false
         #       thread.exit
         #    end
         # end
      end
   end
end