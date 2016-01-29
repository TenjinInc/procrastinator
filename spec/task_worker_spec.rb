require 'spec_helper'

module Procrastinator
   class SuccessTask
      def run

      end
   end

   class FailTask
      def run
         raise('derp')
      end
   end

   describe TaskWorker do
      let(:default_args) do
         {id:             0,
          run_at:         0,
          initial_run_at: 0,
          attempts:       0,
          timeout:        0,
          max_attempts:   2,
          last_fail_at:   0,
          task:           YAML.dump(SuccessTask.new)}
      end

      describe '#inititalize' do
         let(:task) { double('task', run: nil) }

         it 'should complain when timeout is negative' do
            stub_yaml(task)

            expect do
               TaskWorker.new(default_args.merge(timeout: -1))
            end.to raise_error(ArgumentError, 'timeout cannot be negative')
         end

         it 'should unpack handler parameter' do
            task     = double('task', run: nil)
            task_yml = YAML.dump(task)

            allow(YAML).to receive(:load).with(task_yml).and_return(task)

            worker = TaskWorker.new(default_args.merge(task: task_yml))

            expect(worker.task).to eq task
         end

         it 'should complain when no handler is given' do
            args = default_args.dup
            args.delete(:task)

            expect do
               TaskWorker.new(args)
            end.to raise_error(ArgumentError, 'missing keyword: task')
         end

         it 'should complain if task does not support #run' do
            task_str = YAML.dump(double('Badtask'))

            expect do
               TaskWorker.new(default_args.merge(task: task_str))
            end.to raise_error(MalformedTaskError, 'given task does not support #run method')
         end
      end

      describe '#work' do

         context 'run hook' do
            it 'should call task #run' do
               task = double('task')

               stub_yaml(task)

               expect(task).to receive(:run)
               allow(task).to receive(:success)

               worker = TaskWorker.new(default_args.merge(task: task))

               worker.work
            end

            it 'should increase number of attempts when #run is called' do
               task = double('task')

               stub_yaml(task)

               allow(task).to receive(:run)
               allow(task).to receive(:success)

               worker = TaskWorker.new(default_args.merge(task: task))

               (1..3).each do |i|
                  worker.work
                  expect(worker.attempts).to eq i
               end
            end
         end

         context 'success hook' do
            it 'should call task #success when #run completes without error' do
               task = double('task')

               stub_yaml(task)

               allow(task).to receive(:run)
               expect(task).to receive(:success)

               worker = TaskWorker.new(default_args.merge(task: task))

               worker.work
            end

            it 'should not call task #success when #run errors' do
               task = FailTask.new

               expect(task).to_not receive(:success)
               allow(task).to receive(:fail)

               stub_yaml(task)

               worker = TaskWorker.new(default_args.merge(task: task))

               worker.work
            end

            it 'should complain to stderr when #success errors' do
               task = SuccessTask.new
               err  ='success block error'

               stub_yaml(task)

               allow(task).to receive(:success).and_raise(err)

               worker = TaskWorker.new(default_args.merge(task: task))

               expect { worker.work }.to output("Success hook error: #{err}\n").to_stderr
            end

            it 'should do nothing if the task does not include #success' do
               worker = TaskWorker.new(default_args.merge(task: YAML.dump(FailTask.new)))

               expect { worker.work }.to_not output.to_stderr
            end

            it 'should blank the error message' do
               worker = TaskWorker.new(default_args.merge(last_error: 'derp', task: YAML.dump(SuccessTask.new)))

               worker.work

               expect(worker.last_error).to be nil
            end

            it 'should blank the error time' do
               worker = TaskWorker.new(default_args.merge(last_fail_at: double('failtime'), task: YAML.dump(SuccessTask.new)))

               worker.work

               expect(worker.last_fail_at).to be nil
            end
         end

         context 'fail hook' do
            it 'should #fail when #run errors' do
               task = double('task')
               err  = StandardError.new('fake error')

               stub_yaml(task)

               allow(task).to receive(:run).and_raise(err)

               worker = TaskWorker.new(default_args.merge(task: task))

               expect(task).to receive(:fail).with(err)

               worker.work
            end

            it 'should #fail when #run duration exceeds timeout' do
               task    = double('task')
               timeout = 0.1 # can't be 0. timeout doesn't actually do timeout stuff if given 0

               stub_yaml(task)

               allow(task).to receive(:run) do
                  sleep(timeout + 0.1)
               end
               expect(task).to receive(:fail).with(Timeout::Error)

               worker = TaskWorker.new(default_args.merge(task: task, timeout: timeout))

               worker.work
            end

            it 'should call #fail if nil max_attempts given and #run errors' do
               task = double('task')

               stub_yaml(task)

               allow(task).to receive(:run).and_raise('fake error')
               expect(task).to receive(:fail)

               worker = TaskWorker.new(default_args.merge(task: task, max_attempts: nil))

               worker.work
            end

            it 'should not #fail when #success errors' do
               task = double('task')

               stub_yaml(task)

               allow(task).to receive(:run)
               allow(task).to receive(:success).and_raise('success block error')
               expect(task).to_not receive(:fail)

               worker = TaskWorker.new(default_args.merge(task: task))

               worker.work
            end

            it 'should not #fail if calling #final_fail' do
               task = double('task')

               stub_yaml(task)

               allow(task).to receive(:run).and_raise('fake error')
               allow(task).to receive(:final_fail)

               worker = TaskWorker.new(default_args.merge(task: task, max_attempts: 0))

               expect(task).to_not receive(:fail) # this is the real expectation

               worker.work
            end

            it 'should handle errors from task #fail' do
               task = double('task')
               err  = 'fail error'

               stub_yaml(task)

               allow(task).to receive(:run).and_raise('run error')
               allow(task).to receive(:fail).and_raise(err)

               worker = TaskWorker.new(default_args.merge(task: task))

               expect { worker.work }.to output("Fail hook error: #{err}\n").to_stderr
            end

            it 'should do nothing if the task does not include #fail' do
               task = double('task')

               stub_yaml(task)

               allow(task).to receive(:run).and_raise('fake error')

               worker = TaskWorker.new(default_args.merge(task: task))

               expect { worker.work }.to_not output.to_stderr
            end

            it 'should record the most recent failure time' do
               task       = double('task')
               start_time = Time.now
               delay      = 100

               stub_yaml(task)

               Timecop.freeze(start_time) do
                  allow(task).to receive(:run) do
                     Timecop.travel(delay)
                     raise 'fake error'
                  end

                  worker = TaskWorker.new(default_args.merge(task: task))

                  worker.work

                  expect(worker.last_fail_at).to eq start_time.to_i + delay
               end
            end

            it 'should reschedule for the future'
            it 'should reschedule on an increasing basis' #TODO: (30 + n_attempts^4) seconds

            it 'should record the error and trace in last_error' do
               worker = TaskWorker.new(default_args.merge(task: YAML.dump(FailTask.new)))
               worker.work

               expect(worker.last_error).to start_with 'Task failed: '
               expect(worker.last_error).to match /(.*\n)+/ # poor version of checking for backtrace, but it works for now
            end
         end

         context 'final_fail hook' do
            it 'should call #final_fail if #run errors more than given max_attempts' do
               max_attempts = 3
               task         = double('task')
               err          = StandardError.new('fake error')

               allow(task).to receive(:run).and_raise(err)
               allow(task).to receive(:fail)

               stub_yaml(task)

               worker = TaskWorker.new(default_args.merge(task: task, max_attempts: max_attempts))

               expect(task).to receive(:final_fail).with(err)

               max_attempts.times do
                  worker.work
               end
            end

            it 'should call #final_fail when the expiry time has passed' # TODO: and record different message

            it 'should not error or call #final_fail if nil max_attempts given' do
               task = double('task')

               allow(task).to receive(:run).and_raise('fake error')
               allow(task).to receive(:fail)

               stub_yaml(task)

               worker = TaskWorker.new(default_args.merge(task: task, max_attempts: nil))

               expect(task).to_not receive(:final_fail)

               worker.work
            end

            it 'should handle errors from #final_fail' do
               task = double('task')
               err  = 'final fail error'

               allow(task).to receive(:run).and_raise('run error')
               allow(task).to receive(:final_fail).and_raise(err)

               stub_yaml(task)

               worker = TaskWorker.new(default_args.merge(task: task, max_attempts: 0))

               expect do
                  worker.work
               end.to output("Final_fail hook error: #{err}\n").to_stderr
            end

            it 'should do nothing if the task does not include #final_fail' do
               worker = TaskWorker.new(default_args.merge(task: YAML.dump(FailTask.new), max_attempts: 0))

               expect do
                  worker.work
               end.to_not output.to_stderr
            end

            it 'should record the final failure time' do
               task       = double('task')
               start_time = Time.now
               delay      = 100

               Timecop.freeze(start_time) do
                  allow(task).to receive(:run) do
                     Timecop.travel(delay)
                     raise 'fake error'
                  end

                  stub_yaml(task)

                  worker = TaskWorker.new(default_args.merge(task: task, max_attempts: 0))

                  worker.work

                  expect(worker.last_fail_at).to eq start_time.to_i + delay
               end
            end

            it 'should mark the task as permanently failed' do
               worker = TaskWorker.new(default_args.merge(task: YAML.dump(FailTask.new), max_attempts: 0))
               worker.work

               expect(worker.run_at).to be nil
            end

            it 'should record the error and trace in last_error' do
               worker = TaskWorker.new(default_args.merge(task: YAML.dump(FailTask.new), max_attempts: 0))
               worker.work

               expect(worker.last_error).to start_with 'Task failed too many times: '
               expect(worker.last_error).to match /(.*\n)+/ # poor version of checking for backtrace, but it works for now
            end
         end
      end

      describe '#too_many_fails?' do
         it 'should be true if no attempts remain' do
            worker = TaskWorker.new(default_args.merge(task: YAML.dump(FailTask.new), attempts: 2, max_attempts: 3))

            worker.work # attempts should now go up to 3

            expect(worker.too_many_fails?).to be true
         end

         it 'should be false if attempts remain' do
            worker = TaskWorker.new(default_args.merge(task: YAML.dump(FailTask.new), attempts: 1, max_attempts: 3))

            worker.work

            expect(worker.too_many_fails?).to be false
         end

         it 'should be false if nil max_attempts is given' do
            worker = TaskWorker.new(default_args.merge(task: YAML.dump(FailTask.new), max_attempts: nil))

            worker.work

            expect(worker.too_many_fails?).to be false
         end
      end

      describe '#successful?' do
         it 'should return true when #run completes without error' do
            worker = TaskWorker.new(default_args.merge(task: YAML.dump(SuccessTask.new)))

            worker.work

            expect(worker.successful?).to be true
         end

         it 'should return false if #run failed' do
            worker = TaskWorker.new(default_args.merge(task: YAML.dump(FailTask.new)))

            worker.work

            expect(worker.successful?).to be false
         end

         it 'should return false if final failure' do
            worker = TaskWorker.new(default_args.merge(task: YAML.dump(FailTask.new), max_attempts: 1))

            worker.work

            expect(worker.successful?).to be false
         end

         it 'should complain if it has not been run yet' do
            worker = TaskWorker.new(default_args.merge(task: YAML.dump(SuccessTask.new)))

            expect { worker.successful? }.to raise_error(RuntimeError, 'you cannot check for success before running #work')
         end
      end

      describe '#to_hash' do
         it 'should return the properties as a hash' do
            id             = double('id')
            run_at         = double('run_at')
            initial_run_at = double('initial_run_at')
            task           = SuccessTask.new
            attempts       = double('attempts')
            last_fail_at   = double('last_fail_at')
            last_error     = double('last_error')


            properties = {id:             id,
                          initial_run_at: initial_run_at,
                          run_at:         run_at,
                          attempts:       attempts,
                          last_fail_at:   last_fail_at,
                          last_error:     last_error,
                          task:           YAML.dump(task)}

            worker = TaskWorker.new(properties)

            #TODO: add: expire_at:

            expect(worker.to_hash).to eq properties
         end
      end
   end
end