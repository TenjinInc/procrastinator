# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe Task do
      let(:queue) { double('test queue', name: :test_queue, max_attempts: nil, timeout: nil) }
      let(:meta) { TaskMetaData.new(queue: queue) }
      let(:handler) { Test::Task::AllHooks.new }
      let(:task) { Task.new(meta, handler) }

      describe '#run' do
         it 'should increase number of attempts when #run is called' do
            (1..3).each do |i|
               task.run
               expect(task.attempts).to eq i
            end
         end

         it 'should call the handler' do
            expect(handler).to receive(:run)

            task.run
         end

         it 'should alias call' do
            expect(handler).to receive(:run)

            task.call
         end

         it 'should blank the error message' do
            meta = TaskMetaData.new(queue: queue, last_error: 'asplode')
            task = Task.new(meta, double('task', run: nil))

            task.run

            expect(meta.last_error).to be nil
         end

         it 'should blank the error time' do
            meta = TaskMetaData.new(queue: queue, last_fail_at: Time.now)
            task = Task.new(meta, double('task', run: nil))

            task.run

            expect(meta.last_fail_at).to be nil
         end

         it 'should attempt task #success' do
            expect(handler).to receive(:success)

            task.run
         end

         it 'should pass the result of #run to #success' do
            result = double('run result')

            allow(handler).to receive(:run).and_return(result)
            expect(handler).to receive(:success).with(result)

            task.run
         end

         it 'should raise an error when queue timeout exceeded' do
            timeout = 0.01 # timeout ignores 0, so instead: teeny tiny timeout
            allow(queue).to receive(:timeout).and_return timeout

            allow(handler).to receive(:run) do
               sleep(timeout + 0.01)
            end

            expect { task.run }.to raise_error Timeout::Error
         end

         context 'expired task' do
            it 'should complain' do
               now  = Time.now - 1
               meta = TaskMetaData.new(queue: queue, expire_at: now)
               task = Task.new(meta, handler)

               expect { task.run }.to raise_error Task::ExpiredError, "task is over its expiry time of #{ now.iso8601 }"
            end

            it 'should NOT call #run' do
               meta = TaskMetaData.new(queue: queue, expire_at: 0)
               task = Task.new(meta, handler)

               expect(handler).to_not receive(:run)
               expect { task.run }.to raise_error Task::ExpiredError
            end
         end

         context 'run error' do
            before(:each) do
               allow(handler).to receive(:run).and_raise 'asplode'
            end

            it 'should still increase number of attempts' do
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

               expect { task.run }.to raise_error RuntimeError, 'asplode'

               expect(meta.last_error).to eq 'cocoon'
               expect(meta.last_fail_at).to eq now
            end

            it 'should NOT attempt task #success' do
               expect(handler).to_not receive(:success)

               expect { task.run }.to raise_error RuntimeError, 'asplode'
            end
         end

         context 'success error' do
            let(:err) { 'task failed successfully' }

            before(:each) do
               allow(handler).to receive(:success).and_raise err
            end

            it 'should report errors from handler #success' do
               expect { task.run }.to output("Success hook error: #{ err }\n").to_stderr
            end
         end
      end

      describe '#fail' do
         let(:fake_error) do
            err = StandardError.new('asplode')
            err.set_backtrace ['first line', 'second line']
            err
         end

         it 'should record the failure in metadata' do
            expect(meta).to receive(:failure).with(fake_error).and_return :fail
            task.fail(fake_error)
         end

         it 'should call the #fail handler hook' do
            expect(handler).to receive(:fail).with(fake_error)
            task.fail(fake_error)
         end

         it 'should capture errors from task #fail' do
            allow(handler).to receive(:fail).and_raise('fail error')

            # output matcher is just to silence expected stderr warning and act as not-raise-error matcher
            expect { task.fail(fake_error) }.to output.to_stderr
         end

         it 'should report errors from task #fail' do
            err = 'fail error'
            allow(handler).to receive(:fail).and_raise(err)

            expect { task.fail(fake_error) }.to output("Fail hook error: #{ err }\n").to_stderr
         end

         it 'should return :fail' do
            expect(task.fail(fake_error)).to eq :fail
         end

         it 'should return :fail even if it breaks' do
            err = 'fail error'
            allow(handler).to receive(:fail).and_raise(err)

            result = nil
            expect do
               result = task.fail(fake_error)
            end.to output.to_stderr

            expect(result).to eq :fail
         end

         context 'final failure' do
            # expired tasks are final failed
            let(:meta) { TaskMetaData.new(queue: queue, expire_at: 0) }

            it 'should call the #final_fail handler hook' do
               expect(handler).to receive(:final_fail).with(fake_error).and_return :final_fail
               task.fail(fake_error)
            end

            it 'should NOT call the #fail handler hook' do
               expect(handler).to_not receive(:fail)
               task.fail(fake_error)
            end

            it 'should report errors from task #final_fail' do
               err = 'fail error'
               allow(handler).to receive(:final_fail).and_raise(err)

               expect { task.fail(fake_error) }.to output("Final_fail hook error: #{ err }\n").to_stderr
            end

            it 'should return :final_fail' do
               expect(task.fail(fake_error)).to eq :final_fail
            end

            it 'should return :final_fail even if it breaks' do
               err = 'fail error'
               allow(handler).to receive(:final_fail).and_raise(err)

               result = nil
               expect do
                  result = task.fail(fake_error)
               end.to output.to_stderr
               expect(result).to eq :final_fail
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
