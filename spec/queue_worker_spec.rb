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
               job1 = {run_at: 1, task: double('task1', run: nil)}
               job2 = {run_at: 2, task: double('task2', run: nil)}
               job3 = {run_at: 3, task: double('task3', run: nil)}

               persister = double('disorganized persister', read_tasks: [job2, job3, job1], update_task: nil, delete_task: nil)
               worker    = QueueWorker.new(name: :queue, persister: persister, update_period: 0.01)
               stub_loop(worker)

               expect(job1[:task]).to receive(:run).ordered
               expect(job2[:task]).to receive(:run).ordered
               expect(job3[:task]).to receive(:run).ordered

               worker.work
            end

            it 'should reload tasks every cycle' do
               job1 = {run_at: 1, task: double('job1')}
               job2 = {run_at: 1, task: double('job2')}

               allow(job1[:task]).to receive(:run) do
                  Timecop.travel(4)
               end
               allow(job2[:task]).to receive(:run) do
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

            it 'should run a TaskWorker for each ready task' do
               task_data1 = {run_at: 1, task: double('task1', run: nil)}
               task_data2 = {run_at: 1, task: double('task2', run: nil)}
               task_data3 = {run_at: 1, task: double('task3', run: nil)}

               [task_data1, task_data2, task_data3].each do |data|
                  expect(TaskWorker).to receive(:new).with(run_at: data[:run_at],
                                                           task:   data[:task]).and_call_original
               end

               persister = double('persister', update_task: nil, delete_task: nil)
               allow(persister).to receive(:read_tasks).and_return([task_data1, task_data2, task_data3])

               worker = QueueWorker.new(name: :queue, persister: persister, update_period: 0)

               stub_loop worker
               worker.work
            end

            it 'should not start more TaskWorkers than max_tasks'
            #set max_tasks to 1, give 2 ready jobs.

            it 'should not start any TaskWorkers for unready tasks'
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
   end
end