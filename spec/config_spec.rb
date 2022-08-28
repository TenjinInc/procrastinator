# frozen_string_literal: true

module Procrastinator
   require 'spec_helper'

   describe Config do
      let(:test_task) { Test::Task::AllHooks }

      describe '#initialize' do
         it 'should yield itself' do
            yielded_instance = nil
            new_instance     = described_class.new { |i| yielded_instance = i }
            expect(yielded_instance).to be new_instance
         end

         it 'should default to the basic CSV task store if none is provided' do
            config = Config.new do |c|
               c.define_queue(:test_queue, test_task)
            end

            created_queue = config.queue(name: :test_queue)

            expect(created_queue.store).to be_a(TaskStore::SimpleCommaStore)
            expect(created_queue.store.path.to_s).to eq TaskStore::SimpleCommaStore::DEFAULT_FILE.to_s
         end

         # immutable to aid with thread-safety and predictability
         it 'should freeze itself' do
            config = Config.new

            expect(config).to be_frozen
         end

         it 'should freeze its queue list' do
            config = Config.new

            expect(config.queues).to be_frozen
         end
      end

      context 'DSL' do
         describe '#with_store' do
            it 'should accept a strategy hash' do
               path = Pathname.new('/some/path/file.csv')

               config = Config.new do |c|
                  c.with_store(csv: path) do
                     c.define_queue(:test_queue, test_task)
                  end
               end

               created_queue = config.queue(name: :test_queue)

               expect(created_queue.store).to be_a(TaskStore::SimpleCommaStore)
               expect(created_queue.store.path).to eq path
            end

            it 'should accept a path and assume the default strategy' do
               ['a string path.csv',
                Pathname.new('/some/path/file.csv')].each do |path|
                  config = Config.new do |c|
                     c.with_store(path) do
                        c.define_queue(:test_queue, test_task)
                     end
                  end

                  created_queue = config.queue(name: :test_queue)

                  expect(created_queue.store).to be_a(TaskStore::SimpleCommaStore)
                  expect(created_queue.store.path).to eq Pathname.new(path)
               end
            end

            it 'should complain about unknown store strategies' do
               path = '/some/path/file.csv'

               expect do
                  Config.new do |c|
                     c.with_store(bogus: path) do
                        # define queues...
                     end
                  end
               end.to raise_error ArgumentError, 'Must pass keyword :csv if specifying a location for CSV file'
            end

            it 'should complain if the task store is nil' do
               expect do
                  Config.new do |c|
                     c.with_store(nil) do
                        # define queues ...
                     end
                  end
               end.to raise_error(ArgumentError, 'task store cannot be nil')
            end

            it 'should require a block' do
               expect do
                  Config.new do |c|
                     c.with_store(double('some storage'))
                  end
               end.to raise_error(ArgumentError, 'with_store must be provided a block')
            end

            it 'should yield to the given block' do
               expect do |block|
                  Config.new do |c|
                     c.with_store(csv: 'something.csv', &block)
                  end
               end.to yield_with_no_args
            end

            it 'should use the provided task store as the new default within the block' do
               expect do |block|
                  Config.new do |c|
                     c.with_store(csv: 'something.csv', &block)
                  end
               end.to yield_with_no_args
            end

            it 'should return the default to original' do
               custom_path = Pathname.new('custom.csv')
               config      = Config.new do |c|
                  c.with_store(csv: custom_path) do
                     c.define_queue(:inner_queue, test_task)
                  end
                  c.define_queue(:outer_queue, test_task)
               end

               expect(config.queue(name: :inner_queue).store.path).to eq(custom_path)
               expect(config.queue(name: :outer_queue).store.path).to eq(Pathname.new(TaskStore::SimpleCommaStore::DEFAULT_FILE))
            end
         end

         describe '#provide_container' do
            it 'should store the container' do
               container = double('block')

               config = Config.new do |c|
                  c.provide_container(container)
               end

               expect(config.container).to be container
            end
         end

         describe '#define_queue' do
            it 'should add a queue with the given name' do
               config = Config.new do |c|
                  c.define_queue(:queue_name_here, test_task)
               end

               queue = config.queues.first

               expect(queue&.name).to eq :queue_name_here
            end

            it 'should require that the queue name NOT be nil' do
               expect do
                  Config.new do |c|
                     c.define_queue(nil, double('taskClass'))
                  end
               end.to raise_error(ArgumentError, 'queue name cannot be nil')
            end

            it 'should add a queue with the given task class' do
               config = Config.new do |c|
                  c.define_queue(:test1, test_task)
               end

               expect(config.queue(name: :test1).task_handler).to be_a test_task
            end

            it 'should require that the queue task class NOT be nil' do
               expect do
                  Config.new do |c|
                     c.define_queue(:queue_name, nil)
                  end
               end.to raise_error(ArgumentError, 'queue task class cannot be nil')
            end

            it 'should add a queue with the given max_attempts' do
               config = Config.new do |c|
                  c.define_queue(:test1, test_task, max_attempts: 3)
               end

               queue = config.queues.first

               expect(queue&.max_attempts).to eq 3
            end

            it 'should add a queue with the given timeout' do
               config = Config.new do |c|
                  c.define_queue(:test1, test_task, timeout: 5)
               end

               queue = config.queues.first

               expect(queue&.timeout).to eq 5
            end

            it 'should add a queue with the given update_period' do
               config = Config.new do |c|
                  c.define_queue(:test1, test_task, update_period: 4)
                  c.define_queue(:test2, test_task, update_period: 8)
               end

               queue1 = config.queues.first || raise('queue missing')
               queue2 = config.queues.last || raise('queue missing')

               expect(queue1.update_period).to eq 4
               expect(queue1.task_handler).to be_a test_task

               expect(queue2.update_period).to eq 8
               expect(queue2.task_handler).to be_a test_task
            end

            context 'storage' do
               let(:storage_path) { Pathname.new('some-storage.csv') }
               let(:persister) { fake_persister([]) }

               it 'should add a queue with the given storage' do
                  config = Config.new do |c|
                     c.define_queue(:test1, test_task, store: persister)
                  end

                  queue = config.queues.first || raise('queue missing')

                  expect(queue.store).to eq persister
               end

               it 'should override default storage with queue defined storage' do
                  config = Config.new do |c|
                     c.with_store(double('some default')) do
                        c.define_queue(:test1, test_task, store: persister)
                     end
                  end

                  expect(config.queues.first&.store).to eq persister
               end

               it 'should interpret a hash as the storage strategy' do
                  config = Config.new do |c|
                     c.define_queue(:test1, test_task, store: {csv: storage_path})
                  end

                  queue = config.queues.first || raise('queue missing')

                  expect(queue.store).to be_a TaskStore::SimpleCommaStore
                  expect(queue.store.path).to eq storage_path
               end

               it 'should interpret a string as the path to the default storage strategy' do
                  config = Config.new do |c|
                     c.define_queue(:test1, test_task, store: storage_path)
                  end

                  queue = config.queues.first || raise('queue missing')

                  expect(queue.store).to be_a TaskStore::SimpleCommaStore
                  expect(queue.store.path).to eq storage_path
               end

               it 'should complain when the store is nil' do
                  expect do
                     Config.new do |c|
                        c.define_queue(:test1, test_task, store: nil)
                     end
                  end.to raise_error(ArgumentError, 'task store cannot be nil')
               end
            end
         end

         describe '#log_with' do
            it 'should set the log directory' do
               dir = '/a/logging/directory'

               config = Config.new do |c|
                  c.log_with(directory: dir)
               end

               expect(config.log_dir.to_s).to eq dir
            end

            it 'should set the log level' do
               lvl    = Logger::FATAL
               config = Config.new do |c|
                  c.log_with(level: lvl)
               end

               expect(config.log_level).to be lvl
            end

            it 'should set the shift_age' do
               age    = 123
               config = Config.new do |c|
                  c.log_with(shift_age: age)
               end

               expect(config.log_shift_age).to be age
            end

            it 'should set the shift_size' do
               size   = 456
               config = Config.new do |c|
                  c.log_with(shift_size: size)
               end

               expect(config.log_shift_size).to be size
            end

            it 'should use default directory if omitted' do
               config = Config.new do |c|
                  c.log_with(level: Logger::DEBUG)
               end

               expect(config.log_dir.to_s).to eq Config::DEFAULT_LOG_DIRECTORY.to_s
            end

            it 'should use default level if omitted' do
               config = Config.new do |c|
                  c.log_with(directory: '/test/log')
               end
               expect(config.log_level).to eq Logger::INFO
            end

            it 'should use default shift age if omitted' do
               config = Config.new do |c|
                  c.log_with(directory: '/test/log')
               end
               expect(config.log_shift_age).to eq Config::DEFAULT_LOG_SHIFT_AGE
            end

            it 'should use default shift size if omitted' do
               config = Config.new do |c|
                  c.log_with(directory: '/test/log')
               end
               # 2**20 = 1 MB
               expect(config.log_shift_size).to eq Config::DEFAULT_LOG_SHIFT_SIZE
            end
         end
      end

      describe 'queue' do
         it 'should return the queue matching the given name' do
            config = Config.new do |c|
               c.define_queue(:reminder, test_task)
               c.define_queue(:thumbnail, test_task)
               c.define_queue(:welcome, test_task)
            end

            queue = config.queue(name: :thumbnail)
            expect(queue).to_not be_nil
            expect(queue.name).to eq :thumbnail
         end

         it 'should no require the name be specified when only one queue' do
            config = Config.new do |c|
               c.define_queue(:thumbnail, test_task)
            end

            queue = config.queue
            expect(queue).to_not be_nil
            expect(queue.name).to eq :thumbnail
         end

         it 'should complain when it is ambiguous' do
            [[:email, :thumbnail],
             [:reminder, :welcome]].each do |queues|
               config = Config.new do |c|
                  c.define_queue(queues.first, test_task)
                  c.define_queue(queues.last, test_task)
               end

               err = "queue must be specified when more than one is defined. Known queues are: :#{ queues.first }, :#{ queues.last }"

               expect { config.queue }.to raise_error ArgumentError, err
            end
         end

         it 'should complain when the requested queue is not registered' do
            [[:email, :thumbnail],
             [:reminder, :welcome]].each do |queues|
               config = Config.new do |c|
                  c.define_queue(queues.first, test_task)
                  c.define_queue(queues.last, test_task)
               end

               defined_str = "Known queues are: :#{ queues.first }, :#{ queues.last }"

               err = %[there is no :bogus queue registered. #{ defined_str }]
               expect { config.queue(name: :bogus) }.to raise_error(ArgumentError, err)

               err = %[there is no :other_bogus queue registered. #{ defined_str }]
               expect { config.queue(name: :other_bogus) }.to raise_error(ArgumentError, err)
            end
         end
      end

      describe '#log_dir' do
         it 'should return the log directory' do
            dir = '/logging/path'

            config = Config.new do |c|
               c.log_with directory: dir
            end

            expect(config.log_dir.to_s).to eq dir
         end
      end
   end
end
