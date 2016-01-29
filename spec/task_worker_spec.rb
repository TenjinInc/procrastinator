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

         it 'should accept id parameter' do
            [double('id1'), double('id2')].each do |id|
               worker = TaskWorker.new(default_args.merge(id: id))

               expect(worker.id).to eq id
            end
         end

         it 'should accept run_at parameter' do
            [double('time1'), double('time2')].each do |time|
               worker = TaskWorker.new(default_args.merge(run_at: time))

               expect(worker.run_at).to eq time
            end
         end

         it 'should accept initial_run_at parameter' do
            [double('time1'), double('time2')].each do |time|
               worker = TaskWorker.new(default_args.merge(initial_run_at: time))

               expect(worker.initial_run_at).to eq time
            end
         end

         it 'should accept expire_at parameter' #do
           # [double('time1'), double('time2')].each do |time|
           #    worker = TaskWorker.new(default_args.merge(expire_at: time))
#
           #    expect(worker.expire_at).to eq time
           # end
         #end

         it 'should complain when timeout is negative' do
            stub_yaml(task)

            expect do
               TaskWorker.new(default_args.merge(timeout: -1))
            end.to raise_error(ArgumentError, 'timeout cannot be negative')
         end

         it 'should accept attempts' do
            (1..3).each do |attempts|
               worker = TaskWorker.new(default_args.merge(attempts: attempts))

               expect(worker.attempts).to eq attempts
            end
         end

         it 'should accept handler parameter' do
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
               task = double('task')

               stub_yaml(task)

               allow(task).to receive(:run).and_raise('fake error')
               expect(task).to_not receive(:success)
               allow(task).to receive(:fail)

               worker = TaskWorker.new(default_args.merge(task: task))

               worker.work
            end

            it 'should complain to stderr when #success errors' do
               task = double('task')
               err  ='success block error'

               stub_yaml(task)

               allow(task).to receive(:run)
               allow(task).to receive(:success).and_raise(err)

               worker = TaskWorker.new(default_args.merge(task: task))

               expect { worker.work }.to output("Success hook error: #{err}\n").to_stderr
            end

            it 'should do nothing if the task does not include #success' do
               task = double('task')

               stub_yaml(task)

               allow(task).to receive(:run)

               worker = TaskWorker.new(default_args.merge(task: task))

               expect { worker.work }.to_not output.to_stderr
            end

            it 'should blank the error message'
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
            it 'should record the error'
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
                  begin
                     worker.work
                  rescue FinalFailError
                     # do nothing. this error is unimportant to the test
                  end
               end.to output("Final_fail hook error: #{err}\n").to_stderr
            end

            it 'should do nothing if the task does not include #final_fail' do
               task = double('task')

               allow(task).to receive(:run).and_raise('fake error')

               stub_yaml(task)

               worker = TaskWorker.new(default_args.merge(task: task, max_attempts: 0))

               expect do
                  begin
                     worker.work
                  rescue FinalFailError
                     # do nothing. this raise is intended and unimportant to the test
                  end
               end.to_not output.to_stderr
            end

            it 'should record the most final failure time' do
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

                  begin
                     worker.work
                  rescue FinalFailError
                     # do nothing. this raise is intended and unimportant to the test
                  end

                  expect(worker.last_fail_at).to eq start_time.to_i + delay
               end
            end

            it 'should mark the task as permanently failed' # TODO: by nilling run_at
            it 'should record the error'

            it 'should call #final_fail when the expiry time has passed' # TODO: and record different message
         end
      end

      describe '#final_fail?' do
         it 'should be true if no attempts remain' do
            task = double('task')

            allow(task).to receive(:run).and_raise('fake error')
            allow(task).to receive(:fail)

            stub_yaml(task)

            worker = TaskWorker.new(default_args.merge(task: task, attempts: 2, max_attempts: 3))

            worker.work # attempts should now go up to 3

            expect(worker.final_fail?).to be true
         end

         it 'should be false if attempts remain' do
            task = double('task')

            allow(task).to receive(:run).and_raise('fake error')
            allow(task).to receive(:fail)

            stub_yaml(task)

            worker = TaskWorker.new(default_args.merge(task: task, attempts: 1, max_attempts: 3))

            worker.work

            expect(worker.final_fail?).to be false
         end

         it 'should be false if nil max_attempts is given' do
            task = double('task')

            allow(task).to receive(:run).and_raise('fake error')
            allow(task).to receive(:fail)

            stub_yaml(task)

            worker = TaskWorker.new(default_args.merge(task: task, max_attempts: nil))

            worker.work

            expect(worker.final_fail?).to be false
         end
      end

      describe '#status' do
         it 'should return :success when #run completes without error' do
            task = double('task')

            allow(task).to receive(:run)
            allow(task).to receive(:success)

            stub_yaml(task)

            worker = TaskWorker.new(default_args.merge(task: task))

            worker.work

            expect(worker.status).to eq :success
         end

         it 'should return :fail if #run failed' do
            task = double('task')

            allow(task).to receive(:run).and_raise('fake error')
            allow(task).to receive(:fail)

            stub_yaml(task)

            worker = TaskWorker.new(default_args.merge(task: task))

            worker.work

            expect(worker.status).to eq :fail
         end

         it 'should return :final_fail if #run final_failed' do
            max_attempts = 3
            task         = double('task')

            allow(task).to receive(:run).and_raise('fake error')
            allow(task).to receive(:final_fail)

            stub_yaml(task)

            worker = TaskWorker.new(default_args.merge(task: task, attempts: max_attempts-1, max_attempts: max_attempts))

            worker.work

            expect(worker.status).to eq :final_fail
         end
      end

      describe '#to_hash' do
         class DummyTask
            def run

            end
         end

         it 'should return the properties as a hash' do
            id             = double('id')
            run_at         = double('run_at')
            initial_run_at = double('initial_run_at')
            task           = DummyTask.new
            attempts       = double('attempts')
            last_fail_at   = double('last_fail_at')

            properties = {id:             id,
                          initial_run_at: initial_run_at,
                          run_at:         run_at,
                          attempts:       attempts,
                          last_fail_at:   last_fail_at,
                          task:           YAML.dump(task)}

            worker = TaskWorker.new(properties)

            #TODO: add:
            # expire_at: ,
            # last_error: ,

            expect(worker.to_hash).to eq properties
         end
      end
   end
end