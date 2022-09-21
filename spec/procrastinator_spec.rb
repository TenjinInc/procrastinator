# frozen_string_literal: true

require 'spec_helper'

module Procrastinator
   describe Procrastinator do
      it 'should have a version number' do
         expect(Procrastinator::VERSION).not_to be nil
      end

      describe '.setup' do
         let(:test_task) { Test::MockTask }
         let(:persister) { Test::Persister.new }

         it 'should provide the block a configuration instance' do
            # allow(Config).to receive(:new).and_yield

            Procrastinator.setup do |config|
               expect(config).to be_a(Config)

               config.define_queue(:setup_test_queue, test_task)
            end
         end

         it 'should return a scheduler configured with config' do
            scheduler = double('scheduler')
            config    = Config.new do |c|
               c.define_queue(:setup_test_queue, test_task, store: persister)
            end

            expect(Config).to receive(:new).and_return(config)
            expect(Scheduler).to receive(:new).with(config).and_return(scheduler)

            returned = Procrastinator.setup do |c|
               # config stuff
            end

            expect(returned).to be scheduler
         end

         it 'should require that a block is provided' do
            expect { Procrastinator.setup }.to raise_error(ArgumentError, 'Procrastinator.setup must be given a block')
         end
      end

      context 'integration tests' do
         let(:tmp_dir) { Pathname.new Dir.mktmpdir('procrastinator-test') }
         let(:tmp_log_dir) { tmp_dir / 'log' }
         let(:storage_path) { tmp_dir / 'shared-queue-test.csv' }
         let(:fail_data_task) do
            Class.new do
               attr_accessor :logger, :scheduler, :container, :data

               def run
                  raise 'snap'
               end
            end
         end

         let(:scheduler) do
            Procrastinator.setup do |env|
               env.with_store csv: storage_path do
                  env.define_queue(:email, Test::Task::LogData, update_period: 0.1)
                  env.define_queue(:thumbnail, Test::Task::LogData, update_period: 0.1)
                  env.define_queue(:crash, fail_data_task, update_period: 0.1, max_attempts: 1)
               end
               env.log_with(directory: tmp_log_dir) # only needed to prevent writing files outside tmp dir
            end
         end

         before(:each) do
            # FakeFS doesn't currently support file locks (used in csv storage)
            FakeFS.deactivate!
         end

         after(:each) do
            FileUtils.remove_entry(tmp_dir)
            FakeFS.activate!
         end

         it 'should store tasks' do
            scheduler.defer(:thumbnail, run_at: '2016-09-19T00:01:02-09:00', data: {path: 'doug-forcett.png'})
            scheduler.defer(:email, run_at: '2016-09-19T00:01:00-07:00', data: 'janet@example.com')
            scheduler.defer(:thumbnail,
                            run_at:    '2018-01-04T00:12:00-09:00',
                            expire_at: '2018-01-04T00:13:00-09:00',
                            data:      {size: 100, path: 'magic-panda.png'})

            expect(storage_path.read).to eq <<~TASKS
               id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data
               "1","thumbnail","2016-09-19T00:01:02-09:00","2016-09-19T00:01:02-09:00","","0","","","{""path"":""doug-forcett.png""}"
               "2","email","2016-09-19T00:01:00-07:00","2016-09-19T00:01:00-07:00","","0","","","""janet@example.com"""
               "3","thumbnail","2018-01-04T00:12:00-09:00","2018-01-04T00:12:00-09:00","2018-01-04T00:13:00-09:00","0","","","{""size"":100,""path"":""magic-panda.png""}"
            TASKS
         end

         it 'should retry tasks' do
            scheduler.defer(:thumbnail, run_at: '2016-09-19T00:01:02-09:00', data: {path: 'doug-forcett.png'})
            scheduler.defer(:email, run_at: '2016-09-19T00:01:00-07:00', data: 'janet@example.com')
            scheduler.defer(:crash, run_at: '2017-10-26T00:00:00-07:00', data: 'derek@example.com')

            scheduler.work.threaded(timeout: 0.25)

            task_line = storage_path.readlines[1..-1].join("\n").split(',')

            expect(task_line[1]).to eq('"crash"') # queue
            expect(task_line[2]).to eq('""') # run at
            expect(task_line[3]).to eq('"2017-10-26T00:00:00-07:00"') # initial run at
            expect(task_line[5]).to eq('"1"') # attempts
         end

         it 'should reschedule tasks' do
            wrong_time = Time.at(0)
            new_time   = Time.parse('2022-09-20T12:00:00-07:00')
            scheduler.defer(:email, run_at: wrong_time, data: 'mendoza@example.com')

            scheduler.reschedule(:email, run_at: wrong_time, data: 'mendoza@example.com').to(run_at: new_time)

            task_line = storage_path.readlines[1..-1].join("\n").split(',')

            expect(task_line[1]).to eq('"email"') # queue
            expect(task_line[2]).to eq('"2022-09-20T12:00:00-07:00"') # run at
            expect(task_line[3]).to eq('"2022-09-20T12:00:00-07:00"') # initial run at
            expect(task_line[5]).to eq('"0"') # attempts
         end

         it 'should keep a log file per queue' do
            scheduler.defer(:thumbnail, run_at: 100, data: {path: 'stars/doug-forcett.png'})
            scheduler.defer(:email, run_at: 500, data: 'janet@example.com')

            scheduler.work.threaded(timeout: 0.25)

            email_log     = tmp_log_dir / 'email-queue-worker.log'
            thumbnail_log = tmp_log_dir / 'thumbnail-queue-worker.log'

            expect(email_log.read).to include('Ran with data: janet@example.com').once
            expect(thumbnail_log.read).to include('Ran with data: {:path=>"stars/doug-forcett.png"}').once
         end
      end
   end
end
