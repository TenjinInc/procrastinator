# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   module Rake
      describe DaemonTasks do
         context 'define' do
            it 'should create an instance and call #define on it' do
               instance = double('daemon tasks')
               expect(described_class).to receive(:new).and_return instance

               expect(instance).to receive(:define)

               described_class.define(scheduler: nil)
            end

            it 'should forward args to #define' do
               scheduler = double('scheduler')
               pid       = 'pidfile.pid'
               block     = proc { '' }

               expect_any_instance_of(described_class).to receive(:define).with(scheduler: scheduler, pid_path: pid, &block)

               described_class.define(scheduler: scheduler, pid_path: pid, &block)
            end
         end

         context '#define' do
            let(:task_factory) { described_class.new }

            it 'should define a start task' do
               task_factory.define(pid_path: nil) { nil }

               expect(::Rake::Task.task_defined?('procrastinator:start')).to be true
            end

            it 'should define an end task' do
               task_factory.define(pid_path: nil) { nil }

               expect(::Rake::Task.task_defined?('procrastinator:stop')).to be true
            end

            it 'should complain when block missing' do
               expect do
                  task_factory.define(pid_path: nil)
               end.to raise_error ArgumentError, 'must provide a scheduler builder block'
            end
         end

         let(:pid) { 12345 }
         let(:task_factory) { described_class.new }

         context 'task procrastinator:start' do
            let(:pid_path) { Pathname.new('pid/path').expand_path }
            let(:scheduler_proxy) { double('scheduler proxy', daemonized!: nil) }
            let(:scheduler) { double('scheduler', work: scheduler_proxy) }
            let(:task) { ::Rake::Task['procrastinator:start'] }

            before(:each) do
               # Resets the task definitions. This is a bit blunt, but works for now.
               ::Rake::Task.clear
            end

            it 'should call daemonized on the given scheduler' do
               task_factory.define { scheduler }

               expect(scheduler_proxy).to receive(:daemonized!)

               expect { task.invoke }.to output.to_stderr
            end

            it 'should show a message' do
               task_factory.define { scheduler }

               msg = 'Starting Procrastinator'

               expect { task.invoke }.to output(include(msg)).to_stderr
            end

            # to use the default path from the scheduler
            it 'should allow pid_path to be omitted' do
               task_factory.define { scheduler }

               expect(scheduler_proxy).to receive(:daemonized!).with Pathname.new('/tmp/procrastinator.pid')

               expect { task.invoke }.to output.to_stderr
            end

            it 'should call daemonized with the given pid_path' do
               task_factory.define(pid_path: pid_path) { scheduler }

               expect(scheduler_proxy).to receive(:daemonized!).with pid_path / 'procrastinator.pid'

               expect { task.invoke }.to output.to_stderr
            end
         end

         context 'task procrastinator:status' do
            let(:task_factory) { described_class.new }
            let(:pid_path) { Pathname.new 'procrastinator.pid' }
            let(:scheduler) { double('scheduler') }
            let(:task) { ::Rake::Task['procrastinator:status'] }

            before(:each) do
               # Resets the task definitions. This is a bit blunt, but works for now.
               ::Rake::Task.clear

               pid_path.write(pid)

               task_factory.define(pid_path: pid_path) { scheduler }
            end

            context 'instance running' do
               before(:each) do
                  allow(Procrastinator::Scheduler::DaemonWorking).to receive(:running?).and_return true
               end

               it 'should say the instance pid' do
                  msg = "Procrastinator pid #{ pid } instance running"

                  expect do
                     task.invoke
                  end.to output(include(msg)).to_stderr
               end
            end

            context 'file exists but instance not running' do
               before(:each) do
                  allow(Procrastinator::Scheduler::DaemonWorking).to receive(:running?).and_return false
               end

               it 'should warn about crashed instance' do
                  msg = "Procrastinator pid #{ pid } is not running. Maybe it crashed?\n"

                  expect do
                     task.invoke
                  end.to output(ending_with(msg)).to_stderr
               end
            end

            context 'pid file missing' do
               before(:each) do
                  pid_path.delete
               end

               it 'should warn about missing file' do
                  msg = "Procrastinator is not running (No such file - /#{ pid_path })\n"

                  expect do
                     task.invoke
                  end.to output(ending_with(msg)).to_stderr
               end
            end
         end

         context 'task procrastinator:stop' do
            let(:pid) { 1234 }
            let(:pid_path) { Pathname.new('pid/procrastinator.pid').expand_path }
            let(:scheduler) { double('scheduler') }
            let(:task) { ::Rake::Task['procrastinator:stop'] }

            before(:each) do
               # Resets the task definitions. This is a bit blunt, but works for now.
               ::Rake::Task.clear

               # backstop to prevent actual calls to kill
               allow(Process).to receive(:kill).with('TERM', pid)

               pid_path.dirname.mkpath
               pid_path.write(pid)

               described_class.define(pid_path: pid_path) { scheduler }
            end

            context 'instance running' do
               before(:each) do
                  allow(Procrastinator::Scheduler::DaemonWorking).to receive(:running?).and_return true
               end

               it 'should call stop! with the pid path' do
                  expect(Process).to receive(:kill).with('TERM', pid)

                  expect do
                     task.invoke
                  end.to output.to_stderr # silencing test output
               end

               it 'should say that it is halted' do
                  msg = "Procrastinator pid #{ pid } halted.\n"

                  expect { task.invoke }.to output(ending_with(msg)).to_stderr
               end
            end

            context 'pid file missing' do
               before(:each) do
                  pid_path.delete
               end

               it 'should report when file is missing' do
                  msg = "Procrastinator is not running (No such file - /pid/procrastinator.pid)\n"

                  expect { task.invoke }.to output(ending_with(msg)).to_stderr
               end
            end

            context 'pid file exists but process missing' do
               before(:each) do
                  allow(Process).to receive(:kill).with('TERM', pid).and_raise Errno::ESRCH
               end

               it 'should report when procrastinator is not running' do
                  msg = "Procrastinator pid #{ pid } is not running. Maybe it crashed?\n"

                  expect { task.invoke }.to output(ending_with(msg)).to_stderr
               end
            end
         end

         context 'task procrastinator:restart' do
            let(:scheduler) { double('scheduler') }

            it 'should call stop and start' do
               described_class.define { scheduler }

               expect(::Rake::Task['procrastinator:restart'].prerequisites).to include 'stop', 'start'
            end
         end
      end
   end
end
