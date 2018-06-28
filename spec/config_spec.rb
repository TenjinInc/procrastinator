module Procrastinator
   require 'spec_helper'

   describe Config do
      let(:config) {Config.new}
      let(:test_task) {Test::Task::AllHooks}

      describe '#load_with' do
         it 'should require a factory block' do
            err = '#load_with must be given a block that produces a persistence handler for tasks'

            expect do
               Config.new.load_with
            end.to raise_error(RuntimeError, err)
         end
      end

      describe '#provide_context' do
         it 'should require a factory block' do
            err = '#provide_context must be given a block that returns a value to be passed to your task event hooks'

            expect do
               Config.new.provide_context
            end.to raise_error(RuntimeError, err)
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

         it 'should complain if task does NOT accept 2 parameters to #run' do
            err = 'task Procrastinator::Test::Task::MissingParam::BadRun must accept 2 parameters to its #run method'

            expect do
               config.define_queue(:test_queue, Test::Task::MissingParam::BadRun)
            end.to raise_error(MalformedTaskError, err)
         end

         it 'should complain if task does NOT accept 2 parameters to #success' do
            err = 'task Procrastinator::Test::Task::MissingParam::BadSuccess must accept 3 parameters to its #success method'

            expect do
               config.define_queue(:test_queue, Test::Task::MissingParam::BadSuccess)
            end.to raise_error(MalformedTaskError, err)
         end

         it 'should complain if task does NOT accept 3 parameters in #fail' do
            err = 'task Procrastinator::Test::Task::MissingParam::BadFail must accept 3 parameters to its #fail method'

            expect do
               config.define_queue(:test_queue, Test::Task::MissingParam::BadFail)
            end.to raise_error(MalformedTaskError, err)
         end

         it 'should complain if task does NOT accept 3 parameters in #final_fail' do
            err = 'task Procrastinator::Test::Task::MissingParam::BadFinalFail must accept 3 parameters to its #final_fail method'

            expect do
               config.define_queue(:test_queue, Test::Task::MissingParam::BadFinalFail)
            end.to raise_error(MalformedTaskError, err)
         end
      end

      describe '#enable_test_mode' do
         it 'should enable test mode' do
            config.enable_test_mode

            expect(config.test_mode?).to be true
         end
      end

      describe '#log_in' do
         it 'should set the log directory' do
            config = Config.new
            dir    = double('dir')

            config.log_in(dir)

            expect(config.log_dir).to be dir
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

      describe '#prefix_processes' do
         it 'should set the process prefix' do
            prefix = double('lvl')

            config.prefix_processes(prefix)

            expect(config.prefix).to be prefix
         end
      end

      describe '#verify' do
         it 'should complain if it does not have a task loader factory defined' do
            config.define_queue(:test, test_task)

            expect {config.verify}.to raise_error(RuntimeError, 'setup block must call #load_with on the environment')
         end

         it 'should complain if it does not have any queues defined' do
            config.load_with {}

            expect {config.verify}.to raise_error(RuntimeError, 'setup block must call #define_queue on the environment')
         end
      end

      describe '#context' do
         it 'should run the context factory and return the result' do
            context = double('block')

            config.provide_context do
               context
            end

            expect(config.context).to be context
         end
      end

      describe '#loader' do
         it 'should run the loader factory and return the result' do
            loader = double('block', read_tasks: nil, create_task: nil, update_task: nil, delete_task: nil)

            config.load_with do
               loader
            end

            expect(config.loader).to be loader
         end

         it 'should complain if the loader is nil' do
            config.load_with {}

            expect {config.loader}.to raise_error(MalformedTaskLoaderError, 'task loader cannot be nil')
         end

         it 'should complain if the loader does not respond to #read_tasks' do
            loader = double('block', create_task: nil, update_task: nil, delete_task: nil)

            config.load_with do
               loader
            end

            err = "task loader #{loader.class} must respond to #read_tasks"

            expect {config.loader}.to raise_error(MalformedTaskLoaderError, err)
         end

         it 'should complain if the loader does not respond to #create_task' do
            loader = double('block', read_tasks: nil, update_task: nil, delete_task: nil)

            config.load_with do
               loader
            end

            err = "task loader #{loader.class} must respond to #create_task"

            expect {config.loader}.to raise_error(MalformedTaskLoaderError, err)
         end

         it 'should complain if the loader does not respond to #update_task' do
            loader = double('block', read_tasks: nil, create_task: nil, delete_task: nil)

            config.load_with do
               loader
            end

            err = "task loader #{loader.class} must respond to #update_task"

            expect {config.loader}.to raise_error(MalformedTaskLoaderError, err)
         end

         it 'should complain if the loader does not respond to #delete_task' do
            loader = double('block', read_tasks: nil, create_task: nil, update_task: nil,)

            config.load_with do
               loader
            end

            err = "task loader #{loader.class} must respond to #delete_task"

            expect {config.loader}.to raise_error(MalformedTaskLoaderError, err)
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
   end
end