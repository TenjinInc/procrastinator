module Procrastinator
   require 'spec_helper'

   describe Config do
      let(:config) {Config.new}
      let(:test_task) {Test::Task::AllHooks}

      context 'DSL' do
         describe '#load_with' do
            include FakeFS::SpecHelpers

            it 'should accept a location hash' do
               path   = '/some/path/file.csv'
               loader = Loader::CSVLoader.new(path)
               expect(Loader::CSVLoader).to receive(:new).with(path).and_return(loader)

               config.load_with(location: path)

               expect(config.loader).to be loader
            end

            it 'should complain about other hash values' do
               path = '/some/path/file.csv'
               expect(Loader::CSVLoader).to_not receive(:new)

               expect do
                  config.load_with(bogus: path)
               end.to raise_error ArgumentError, 'Must pass keyword :location if specifying a location for CSV file'

               expect(config.loader).to be_nil
            end

            it 'should complain if the loader is nil' do
               expect do
                  config.load_with(nil)
               end.to raise_error(MalformedTaskLoaderError, 'task loader cannot be nil')
            end

            it 'should complain if the loader does not respond to #read' do
               bad_loader = double('block', create: nil, update: nil, delete: nil)

               err = "task loader #{bad_loader.class} must respond to #read"

               expect {config.load_with(bad_loader)}.to raise_error(MalformedTaskLoaderError, err)
            end

            it 'should complain if the loader does not respond to #create' do
               bad_loader = double('block', read: nil, update: nil, delete: nil)

               err = "task loader #{bad_loader.class} must respond to #create"

               expect {config.load_with(bad_loader)}.to raise_error(MalformedTaskLoaderError, err)
            end

            it 'should complain if the loader does not respond to #update' do
               bad_loader = double('block', read: nil, create: nil, delete: nil)

               err = "task loader #{bad_loader.class} must respond to #update"

               expect {config.load_with(bad_loader)}.to raise_error(MalformedTaskLoaderError, err)
            end

            it 'should complain if the loader does not respond to #delete' do
               bad_loader = double('block', read: nil, create: nil, update: nil,)

               err = "task loader #{bad_loader.class} must respond to #delete"

               expect {config.load_with(bad_loader)}.to raise_error(MalformedTaskLoaderError, err)
            end
         end

         describe '#provide_context' do
            it 'should store the context' do
               context = double('block')

               config.provide_context(context)

               expect(config.context).to be context
            end
         end

         describe '#define_queue' do
            it 'should require that the queue name NOT be nil' do
               expect {config.define_queue(nil, double('taskClass'))}.to raise_error(ArgumentError, 'queue name cannot be nil')
            end

            it 'should require that the queue task class NOT be nil' do
               expect {config.define_queue(:queue_name, nil)}.to raise_error(ArgumentError, 'queue task class cannot be nil')
            end

            it 'should add a queue with its timeout, max_tasks, max_attempts, update_period' do
               config.define_queue(:test1, test_task,
                                   timeout:       1,
                                   max_tasks:     2,
                                   max_attempts:  3,
                                   update_period: 4)
               config.define_queue(:test2, test_task,
                                   timeout:       5,
                                   max_tasks:     6,
                                   max_attempts:  7,
                                   update_period: 8)

               queue1 = config.queues.first
               queue2 = config.queues.last

               expect(queue1.timeout).to eq 1
               expect(queue1.max_tasks).to eq 2
               expect(queue1.max_attempts).to eq 3
               expect(queue1.update_period).to eq 4
               expect(queue1.task_class).to eq test_task

               expect(queue2.timeout).to eq 5
               expect(queue2.max_tasks).to eq 6
               expect(queue2.max_attempts).to eq 7
               expect(queue2.update_period).to eq 8
               expect(queue2.task_class).to eq test_task
            end

            it 'should complain if the task class does NOT support #run' do
               klass = double('bad_task_class')

               expect do
                  allow(klass).to receive(:method_defined?) do |name|
                     name != :run
                  end

                  config.define_queue(:test_queue, klass)
               end.to raise_error(MalformedTaskError, "task #{klass} does not support #run method")
            end

            it 'should complain if task #run expects parameters' do
               klass = Procrastinator::Test::Task::MissingParam::ArgRun

               err = "task #{klass} cannot require parameters to its #run method"

               expect do
                  config.define_queue(:test_queue, klass)
               end.to raise_error(MalformedTaskError, err)
            end

            it 'should complain if task does NOT accept 1 parameter to #success' do
               [Procrastinator::Test::Task::MissingParam::NoArgSuccess,
                Procrastinator::Test::Task::MissingParam::MultiArgSuccess].each do |klass|
                  err = "task #{klass} must accept 1 parameter to its #success method"

                  expect do
                     config.define_queue(:test_queue, klass)
                  end.to raise_error(MalformedTaskError, err)
               end
            end

            it 'should complain if task does NOT accept 1 parameter in #fail' do
               [Procrastinator::Test::Task::MissingParam::NoArgFail,
                Procrastinator::Test::Task::MissingParam::MultiArgFail].each do |klass|
                  err = "task #{klass} must accept 1 parameter to its #fail method"

                  expect do
                     config.define_queue(:test_queue, klass)
                  end.to raise_error(MalformedTaskError, err)
               end
            end

            it 'should complain if task does NOT accept 1 parameter in #final_fail' do
               [Procrastinator::Test::Task::MissingParam::NoArgFinalFail,
                Procrastinator::Test::Task::MissingParam::MultiArgFinalFail].each do |klass|

                  err = "task #{klass} must accept 1 parameter to its #final_fail method"

                  expect do
                     config.define_queue(:test_queue, klass)
                  end.to raise_error(MalformedTaskError, err)
               end
            end
         end

         describe '#enable_test_mode' do
            it 'should enable test mode' do
               config.enable_test_mode

               expect(config.test_mode?).to be true
            end
         end

         describe '#log_inside' do
            it 'should set the log directory' do
               config = Config.new
               dir    = '/a/logging/directory'

               config.log_inside(dir)

               expect(config.log_dir.to_s).to eq dir
            end
         end

         describe '#log_at_level' do
            let(:config) {Config.new}

            it 'should set the log level' do
               lvl = double('lvl')

               config.log_at_level(lvl)

               expect(config.log_level).to be lvl
            end
         end

         describe '#each_process' do
            it 'should set the process prefix' do
               prefix = double('lvl')

               config.each_process(prefix: prefix)

               expect(config.prefix).to be prefix
            end

            it 'should default to a nil process prefix' do
               config.each_process

               expect(config.prefix).to be_nil
            end

            it 'should set the pid directory' do
               config = Config.new
               dir    = '/some/dir'

               config.each_process pid_dir: dir

               expect(config.pid_dir).to be_a Pathname
               expect(config.pid_dir.to_s).to eq dir
            end

            it 'should default to a known default directory' do
               config.each_process

               expect(config.pid_dir.to_s).to eq Config::DEFAULT_PID_DIRECTORY
            end
         end
      end

      describe '#setup' do
         it 'should yield itself' do
            config.define_queue(:test_queue, test_task)

            expect {|b| config.setup &b}.to yield_with_args(config)
         end

         it 'should use the given test mode' do
            [true, false].each do |value|
               config = Config.new

               config.setup(value) do |c|
                  c.define_queue(:test, test_task)
                  c.load_with(Test::Persister.new)
               end

               expect(config.test_mode?).to be value
            end
         end

         it 'should default to the basic CSV task loader if none is provided' do
            config = Config.new

            config.setup do |c|
               c.define_queue(:test_queue, test_task)
            end

            expect(config.loader).to be_a(Procrastinator::Loader::CSVLoader)
         end

         it 'should complain if it does not have any queues defined' do
            config = Config.new

            expect do
               config.setup do |c|
                  c.load_with(Test::Persister.new)
               end
            end.to raise_error(RuntimeError, 'setup block must call #define_queue on the environment')
         end
      end

      describe '#run_process_block' do
         it 'should run the stored block' do
            block = Proc.new {true}

            config.each_process &block

            expect(config.run_process_block).to be true
         end
      end

      describe '#queues_string' do
         it 'should return queue names with symbol formatting' do
            config.define_queue(:test1, test_task)

            expect(config.queues_string).to eq ':test1'
         end

         it 'should return queue names in a comma list' do
            config.define_queue(:test1, test_task)
            config.define_queue(:test2, test_task)
            config.define_queue(:test3, test_task)

            expect(config.queues_string).to eq ':test1, :test2, :test3'
         end
      end

      describe '#log_dir' do
         it 'should return the log direcory' do
            dir = '/logging/path'

            config.log_inside dir

            expect(config.log_dir.to_s).to eq dir
         end

         it 'should return false if test_mode is enabled' do
            config.enable_test_mode
            config.log_inside 'path'

            expect(config.log_dir).to be false
         end
      end
   end
end
