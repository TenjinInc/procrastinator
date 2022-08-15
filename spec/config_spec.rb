# frozen_string_literal: true

module Procrastinator
   require 'spec_helper'

   describe Config do
      let(:config) { Config.new }
      let(:test_task) { Test::Task::AllHooks }

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

               err = "task loader #{ bad_loader.class } must respond to #read"

               expect { config.load_with(bad_loader) }.to raise_error(MalformedTaskLoaderError, err)
            end

            it 'should complain if the loader does not respond to #create' do
               bad_loader = double('block', read: nil, update: nil, delete: nil)

               err = "task loader #{ bad_loader.class } must respond to #create"

               expect { config.load_with(bad_loader) }.to raise_error(MalformedTaskLoaderError, err)
            end

            it 'should complain if the loader does not respond to #update' do
               bad_loader = double('block', read: nil, create: nil, delete: nil)

               err = "task loader #{ bad_loader.class } must respond to #update"

               expect { config.load_with(bad_loader) }.to raise_error(MalformedTaskLoaderError, err)
            end

            it 'should complain if the loader does not respond to #delete' do
               bad_loader = double('block', read: nil, create: nil, update: nil)

               err = "task loader #{ bad_loader.class } must respond to #delete"

               expect { config.load_with(bad_loader) }.to raise_error(MalformedTaskLoaderError, err)
            end
         end

         describe '#provide_container' do
            it 'should store the container' do
               container = double('block')

               config.provide_container(container)

               expect(config.container).to be container
            end
         end

         describe '#define_queue' do
            it 'should require that the queue name NOT be nil' do
               expect { config.define_queue(nil, double('taskClass')) }.to raise_error(ArgumentError, 'queue name cannot be nil')
            end

            it 'should require that the queue task class NOT be nil' do
               expect { config.define_queue(:queue_name, nil) }.to raise_error(ArgumentError, 'queue task class cannot be nil')
            end

            it 'should add a queue with its timeout, max_attempts, update_period' do
               config.define_queue(:test1, test_task,
                                   timeout:       1,
                                   max_attempts:  3,
                                   update_period: 4)
               config.define_queue(:test2, test_task,
                                   timeout:       5,
                                   max_attempts:  7,
                                   update_period: 8)

               queue1 = config.queues.first
               queue2 = config.queues.last

               expect(queue1.timeout).to eq 1
               expect(queue1.max_attempts).to eq 3
               expect(queue1.update_period).to eq 4
               expect(queue1.task_class).to eq test_task

               expect(queue2.timeout).to eq 5
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
               end.to raise_error(MalformedTaskError, "task #{ klass } does not support #run method")
            end

            it 'should complain if task #run expects parameters' do
               klass = Procrastinator::Test::Task::MissingParam::ArgRun

               err = "task #{ klass } cannot require parameters to its #run method"

               expect do
                  config.define_queue(:test_queue, klass)
               end.to raise_error(MalformedTaskError, err)
            end

            it 'should complain if task does NOT accept 1 parameter to #success' do
               [Procrastinator::Test::Task::MissingParam::NoArgSuccess,
                Procrastinator::Test::Task::MissingParam::MultiArgSuccess].each do |klass|
                  err = "task #{ klass } must accept 1 parameter to its #success method"

                  expect do
                     config.define_queue(:test_queue, klass)
                  end.to raise_error(MalformedTaskError, err)
               end
            end

            it 'should complain if task does NOT accept 1 parameter in #fail' do
               [Procrastinator::Test::Task::MissingParam::NoArgFail,
                Procrastinator::Test::Task::MissingParam::MultiArgFail].each do |klass|
                  err = "task #{ klass } must accept 1 parameter to its #fail method"

                  expect do
                     config.define_queue(:test_queue, klass)
                  end.to raise_error(MalformedTaskError, err)
               end
            end

            it 'should complain if task does NOT accept 1 parameter in #final_fail' do
               [Procrastinator::Test::Task::MissingParam::NoArgFinalFail,
                Procrastinator::Test::Task::MissingParam::MultiArgFinalFail].each do |klass|
                  err = "task #{ klass } must accept 1 parameter to its #final_fail method"

                  expect do
                     config.define_queue(:test_queue, klass)
                  end.to raise_error(MalformedTaskError, err)
               end
            end
         end

         describe '#log_with' do
            let(:config) { Config.new }

            it 'should set the log directory' do
               dir = '/a/logging/directory'

               config.log_with(directory: dir)

               expect(config.log_dir.to_s).to eq dir
            end

            it 'should set the log level' do
               lvl = Logger::FATAL

               config.log_with(level: lvl)

               expect(config.log_level).to be lvl
            end

            it 'should set the shift_age' do
               age = 123

               config.log_with(shift_age: age)

               expect(config.log_shift_age).to be age
            end

            it 'should set the shift_size' do
               size = 456

               config.log_with(shift_size: size)

               expect(config.log_shift_size).to be size
            end

            it 'should use default directory if omitted' do
               config.log_with(level: Logger::DEBUG)

               expect(config.log_dir).to eq Config::DEFAULT_LOG_DIRECTORY
            end

            it 'should use default level if omitted' do
               config.log_with(directory: '/test/log')

               expect(config.log_level).to eq Logger::INFO
            end

            it 'should use default shift age if omitted' do
               config.log_with(directory: '/test/log')

               expect(config.log_shift_age).to eq Config::DEFAULT_LOG_SHIFT_AGE
            end

            it 'should use default shift size if omitted' do
               config.log_with(directory: '/test/log')

               # 2**20 = 1 MB
               expect(config.log_shift_size).to eq Config::DEFAULT_LOG_SHIFT_SIZE
            end
         end
      end

      describe '#setup' do
         it 'should yield itself' do
            config.define_queue(:test_queue, test_task)

            expect { |b| config.setup(&b) }.to yield_with_args(config)
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
            end.to raise_error(SetupError, SetupError::ERR_NO_QUEUE)
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

            config.log_with directory: dir

            expect(config.log_dir.to_s).to eq dir
         end
      end
   end
end
