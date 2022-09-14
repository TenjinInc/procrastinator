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
               task_factory.define(scheduler: nil, pid_path: nil)

               expect(::Rake::Task.task_defined?('procrastinator:start')).to be true
            end

            it 'should define an end task' do
               task_factory.define(scheduler: nil, pid_path: nil)

               expect(::Rake::Task.task_defined?('procrastinator:stop')).to be true
            end

            # to use the default path from the scheduler
            it 'should require scheduler is provided' do
               expect do
                  task_factory.define
               end.to raise_error(ArgumentError, 'missing keyword: scheduler')
            end
         end

         context 'task procrastinator:start' do
            let(:task_factory) { described_class.new }

            let(:pid_path) { Pathname.new('pid/path').expand_path }
            let(:scheduler_proxy) { double('scheduler proxy') }
            let(:scheduler) { double('scheduler', work: scheduler_proxy) }
            let(:task) { ::Rake::Task['procrastinator:start'] }

            before(:each) do
               # Resets the task definitions. This is a bit blunt, but works for now.
               ::Rake::Task.clear
            end

            it 'should call daemonized on the given scheduler' do
               task_factory.define(scheduler: scheduler)

               expect(scheduler_proxy).to receive(:daemonized!)

               task.invoke
            end

            # to use the default path from the scheduler
            it 'should allow pid_path to be omitted' do
               task_factory.define(scheduler: scheduler)

               expect(scheduler_proxy).to receive(:daemonized!).with Pathname.new('/var/run/procrastinator.pid')

               task.invoke
            end

            it 'should call daemonized with the given pid_path' do
               task_factory.define(scheduler: scheduler, pid_path: pid_path)

               expect(scheduler_proxy).to receive(:daemonized!).with pid_path / 'procrastinator.pid'

               task.invoke
            end

            it 'should call daemonized with the post daemon block' do
               block = proc { '' }

               task_factory.define(scheduler: scheduler, pid_path: pid_path, &block)

               expect(scheduler_proxy).to receive(:daemonized!).with block

               task.invoke
            end
         end

         context 'task procrastinator:status' do
            let(:task_factory) { described_class.new }
            let(:pid_path) { 'procrastinator.pid' }
            let(:scheduler) { double('scheduler') }
            let(:task) { ::Rake::Task['procrastinator:status'] }
            let(:pid) { 12345 }

            before(:each) do
               # Resets the task definitions. This is a bit blunt, but works for now.
               ::Rake::Task.clear

               allow(Procrastinator::Scheduler::DaemonWorking).to receive(:running?).and_return status
            end

            context 'instance running' do
               let(:status) { true }

               it 'should say the instance pid' do
                  Pathname.new(pid_path).write(pid)
                  task_factory.define(scheduler: scheduler, pid_path: pid_path)

                  msg = "Procrastinator instance running (pid #{ pid })\n"

                  expect do
                     task.invoke
                  end.to output(msg).to_stderr
               end

               it 'should use the default' do
                  pid_path = Pathname.new('/var/run/procrastinator.pid')
                  pid_path.dirname.mkpath
                  pid_path.write(pid)
                  task_factory.define(scheduler: scheduler)

                  msg = "Procrastinator instance running (pid #{ pid })\n"

                  expect do
                     task.invoke
                  end.to output(msg).to_stderr
               end
            end

            context 'instance not running' do
               let(:status) { false }

               it 'should say so' do
                  task_factory.define(scheduler: scheduler, pid_path: pid_path)

                  msg = "No Procrastinator instance detected for /#{ pid_path }\n"

                  expect do
                     task.invoke
                  end.to output(msg).to_stderr
               end
            end
         end

         context 'task procrastinator:stop' do
            let(:task_factory) { described_class.new }
            let(:pid_path) { Pathname.new('procrastinator.pid').expand_path }
            let(:scheduler) { double('scheduler') }
            let(:task) { ::Rake::Task['procrastinator:stop'] }

            before(:each) do
               # Resets the task definitions. This is a bit blunt, but works for now.
               ::Rake::Task.clear
            end

            it 'should call stop! with the pid path' do
               task_factory.define(scheduler: scheduler, pid_path: pid_path)

               expect(Procrastinator::Scheduler::DaemonWorking).to receive(:halt!).with(pid_path)

               task.invoke
            end
         end
      end
   end
end
