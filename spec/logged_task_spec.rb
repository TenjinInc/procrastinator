# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe LoggedTask do
      let(:data_str) { JSON.dump('itsa me, a data-o') }
      let(:task_handler) { Test::Task::AllHooks.new }
      let(:meta) { TaskMetaData.new(id: 1, queue: queue, data: data_str) }
      let(:queue) { Procrastinator::Queue.new(name: :test_queue, task_class: Test::Task::AllHooks, store: fake_persister) }
      let(:task) { Task.new(meta, task_handler) }

      let(:log_file) { Pathname.new('tasklog.log') }
      let(:logger) { Logger.new(log_file.to_s, formatter: Config::DEFAULT_LOG_FORMATTER) }

      before(:each) do
         # Needed because loggers use flock internally
         allow_any_instance_of(FakeFS::File).to receive(:flock)
      end

      describe '#inititalize' do
         it 'should remember the given logger' do
            logger = double(:logger)
            task   = LoggedTask.new(task, logger: logger)
            expect(task.logger).to eq logger
         end

         it 'should build a default logger' do
            task = LoggedTask.new(task)
            expect(task.logger).to be_a Logger
         end

         it 'should complain when logger is nil' do
            expect { LoggedTask.new(task, logger: nil) }.to raise_error ArgumentError, 'Logger cannot be nil'
         end
      end

      describe '#run' do
         let(:wrapper) { LoggedTask.new(task, logger: logger) }
         it 'should call task #run' do
            expect(task).to receive(:run)

            wrapper.run
         end

         it 'should log #run at info level' do
            wrapper.run

            msg = "Task completed: #{ queue.name.to_sym }#1 [#{ data_str }]"
            expect(log_file).to include_log_line 'INFO', msg
         end

         it 'should capture logging errors' do
            allow(logger).to receive(:info).and_raise 'blorp'
            expect do
               expect do
                  wrapper.run
               end.to output.to_stderr # output captured for silence
            end.to_not raise_error # real test here
         end

         it 'should NOT capture run errors' do
            allow(task_handler).to receive(:run).and_raise 'blorp'
            expect { wrapper.run }.to raise_error(RuntimeError, 'blorp')
         end

         it 'should report logging errors' do
            err = 'blorp'
            allow(logger).to receive(:info).and_raise err
            expect { wrapper.run }.to output("Task logging error: #{ err }\n").to_stderr
         end
      end

      describe '#fail' do
         let(:fail_handler) { Test::Task::Fail.new }
         let(:fail_task) { Task.new(meta, fail_handler) }

         let(:wrapper) { LoggedTask.new(fail_task, logger: logger) }

         let(:fake_error) { StandardError.new('asplode') }

         it 'should call #fail on task' do
            wrapper.fail(fake_error)

            expect(log_file).to include_log_line 'ERROR', "Task failed: #{ queue.name }#1 [#{ data_str }]"
         end

         it 'should return #fail result' do
            result = double('fail result')
            allow(fail_task).to receive(:fail).and_return result

            expect(wrapper.fail(fake_error)).to eq result
         end

         it 'should log #fail at error level' do
            wrapper.fail(fake_error)

            expect(log_file).to include_log_line 'ERROR', "Task failed: #{ queue.name }#1 [#{ data_str }]"
         end

         it 'should log #final_fail at error level' do
            meta      = TaskMetaData.new(id: 1, queue: queue, data: data_str, expire_at: 0)
            fail_task = Task.new(meta, fail_handler)

            wrapper = LoggedTask.new(fail_task, logger: logger)

            wrapper.fail(fake_error)

            expect(log_file).to include_log_line 'ERROR', "Task final_failed: #{ queue.name }#1 [#{ data_str }]"
         end

         it 'should capture logging errors' do
            allow(logger).to receive(:error).and_raise 'blorp'
            expect do
               expect do
                  wrapper.fail(fake_error)
               end.to output.to_stderr # for test terminal quiet
            end.to_not raise_error # real test
         end

         it 'should NOT capture fail errors' do
            allow(fail_task).to receive(:fail).and_raise 'blorp'
            expect { wrapper.fail(fake_error) }.to raise_error RuntimeError, 'blorp'
         end

         it 'should report logging errors' do
            err = 'blorp'
            allow(logger).to receive(:error).and_raise err
            expect { wrapper.fail(fake_error) }.to output("Task logging error: #{ err }\n").to_stderr
         end
      end
   end
end
