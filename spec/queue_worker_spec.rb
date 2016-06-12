require 'spec_helper'

module Procrastinator
   class SuccessTask
      def run

      end
   end

   class FailTask
      def run
         raise 'derp'
      end
   end

   describe QueueWorker do
      let(:persister) { double('loader', read_tasks: [], update_task: nil, delete_task: nil) }

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
         it 'should wait for update_period' do
            [0.01, 0.02].each do |period|
               worker = QueueWorker.new(name: :queue, persister: persister, update_period: period)

               expect(worker).to receive(:loop) do |&block|
                  block.call
               end

               expect(worker).to receive(:sleep).with(period)

               worker.work
            end
         end

         it 'should cyclically call #act' do
            worker = QueueWorker.new(name: :queue, persister: persister, update_period: 0.1)

            allow(worker).to receive(:sleep) # stub sleep

            n_loops = 3

            # control looping, otherwise infiniloop by design
            allow(worker).to receive(:loop) do |&block|
               n_loops.times { block.call }
            end

            expect(worker).to receive(:act).exactly(n_loops).times

            worker.work
         end
      end

      describe '#act' do
         context 'loading tasks' do
            it 'should pass the given queue to its persister' do
               [:email, :cleanup].each do |queue|
                  worker = QueueWorker.new(name: queue, persister: persister, update_period: 0.01)

                  expect(persister).to receive(:read_tasks).with(queue)

                  worker.act
               end
            end

            it 'should sort tasks by run_at' do
               task1 = SuccessTask.new
               task2 = SuccessTask.new
               task3 = SuccessTask.new

               job1 = {id: 4, run_at: 1, initial_run_at: 0, task: YAML.dump(task1)}
               job2 = {id: 5, run_at: 2, initial_run_at: 0, task: YAML.dump(task2)}
               job3 = {id: 6, run_at: 3, initial_run_at: 0, task: YAML.dump(task3)}

               allow(YAML).to receive(:load).and_return(task1, task2, task3)

               persister = double('disorganized persister', read_tasks: [job2, job3, job1], update_task: nil, delete_task: nil)
               worker    = QueueWorker.new(name: :queue, persister: persister, update_period: 0.01)

               expect(task1).to receive(:run).ordered
               expect(task2).to receive(:run).ordered
               expect(task3).to receive(:run).ordered

               worker.act
            end

            it 'should reload tasks every cycle' do
               task1 = double('task1')
               task2 = double('task2')

               task1_duration = 4
               task2_duration = 6

               allow(task1).to receive(:run) do
                  Timecop.travel(task1_duration)
               end
               allow(task2).to receive(:run) do
                  Timecop.travel(task2_duration)
               end

               job1 = {run_at: 1, task: task1}
               job2 = {run_at: 1, task: task2}

               allow(persister).to receive(:read_tasks).and_return([job1], [job2])

               allow(YAML).to receive(:load).and_return(task1, task2)

               start_time = Time.now

               Timecop.freeze(start_time) do
                  worker = QueueWorker.new(name: :queue, persister: persister, update_period: 0.00)

                  worker.act
                  worker.act

                  expect(Time.now.to_i).to eq start_time.to_i + task1_duration + task2_duration
               end
            end

            it 'should run a TaskWorker with all the data' do
               task_double = double('task', run: nil)
               task_data   = {run_at: 1, task: YAML.dump(task_double)}

               allow(YAML).to receive(:load).and_return(task_double)

               expect(TaskWorker).to receive(:new).with(task_data).and_call_original

               persister = double('persister', update_task: nil, delete_task: nil)
               allow(persister).to receive(:read_tasks).and_return([task_data])

               worker = QueueWorker.new(name: :queue, persister: persister, update_period: 0)

               worker.act
            end

            it 'should run a TaskWorker for each ready task' do
               task_data1 = {run_at: 1, task: YAML.dump(SuccessTask.new)}
               task_data2 = {run_at: 1, task: YAML.dump(SuccessTask.new)}
               task_data3 = {run_at: 1, task: YAML.dump(SuccessTask.new)}

               expect(TaskWorker).to receive(:new).exactly(3).times.and_call_original

               persister = double('persister', update_task: nil, delete_task: nil)
               allow(persister).to receive(:read_tasks).and_return([task_data1, task_data2, task_data3])

               worker = QueueWorker.new(name: :queue, persister: persister, update_period: 0)

               worker.act
            end

            it 'should not start any TaskWorkers for unready tasks' do
               now = Time.now

               task_data1 = {run_at: now, task: YAML.dump(SuccessTask.new)}
               task_data2 = {run_at: now + 1, task: YAML.dump(SuccessTask.new)}

               expect(TaskWorker).to receive(:new).ordered.and_call_original
               expect(TaskWorker).to_not receive(:new).ordered.and_call_original

               persister = double('persister', update_task: nil, delete_task: nil)
               allow(persister).to receive(:read_tasks).and_return([task_data1, task_data2])

               worker = QueueWorker.new(name: :queue, persister: persister, update_period: 0)

               Timecop.freeze(now) do
                  worker.act
               end
            end

            it 'should not start more TaskWorkers than max_tasks' do
               task_data1 = {run_at: 1, task: YAML.dump(SuccessTask.new)}
               task_data2 = {run_at: 2, task: YAML.dump(SuccessTask.new)}

               expect(TaskWorker).to receive(:new).with(task_data1).and_call_original
               expect(TaskWorker).to_not receive(:new).with(task_data2).and_call_original

               persister = double('persister', update_task: nil, delete_task: nil)
               allow(persister).to receive(:read_tasks).and_return([task_data1, task_data2])

               worker = QueueWorker.new(name: :queue, persister: persister, update_period: 0, max_tasks: 1)

               worker.act
            end
         end


         context 'TaskWorker succeeds' do
            it 'should delete the task' do
               task_data = {id: double('id'), task: YAML.dump(SuccessTask.new)}

               allow(persister).to receive(:read_tasks).and_return([task_data])

               worker = QueueWorker.new(name: :queue, persister: persister, update_period: 0, max_tasks: 1)

               expect(persister).to receive(:delete_task).with(task_data[:id])

               worker.act
            end
         end

         context 'TaskWorker fails or fails For The Last Time' do
            # to do: it should promote captain Piett to admiral

            it 'should update the task' do
               [0, 1].each do |max_attempts|
                  run_at    = double('run_at', to_i: 0)
                  task_data = {run_at: run_at, task: YAML.dump(FailTask.new)}
                  task_hash = {stub: :hash}

                  allow(persister).to receive(:read_tasks).and_return([task_data])

                  allow_any_instance_of(TaskWorker).to receive(:to_hash).and_return(task_hash)

                  worker = QueueWorker.new(name: :queue, persister: persister, update_period: 0, max_attempts: max_attempts)

                  expect(persister).to receive(:update_task).with(task_hash.merge(queue: worker.name))

                  worker.act
               end
            end
         end
      end
   end
end