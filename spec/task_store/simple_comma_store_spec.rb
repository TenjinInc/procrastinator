# frozen_string_literal: true

require 'spec_helper'
require 'pathname'
require 'tmpdir'

module Procrastinator
   module TaskStore
      describe SimpleCommaStore do
         describe 'initialize' do
            it 'should accept a path argument' do
               store = described_class.new 'testfile.csv'
               expect(store.path.to_s).to eq '/testfile.csv'
            end

            it 'should provide a default path argument' do
               store = described_class.new

               expect(store.path.to_s).to eq(Pathname.new(SimpleCommaStore::DEFAULT_FILE).expand_path.to_s)
            end

            it 'should interpret an absolute path' do
               store = described_class.new 'some/relative/../path.csv'

               expect(store.path.to_s).to eq '/some/path.csv'
            end

            it 'should add a .csv extension to the path if missing extension' do
               store = SimpleCommaStore.new 'plainfile'

               expect(store.path.to_s).to eq('/plainfile.csv')
            end

            it 'should add a default filename if the provided path is a directory name' do
               slash_end_path = '/some/place/'

               store = SimpleCommaStore.new(slash_end_path)

               expect(store.path.to_s).to eq("#{ slash_end_path }#{ SimpleCommaStore::DEFAULT_FILE }")
            end

            it 'should add a default filename if the provided path is an existing directory' do
               existing_dir = Pathname.new('test_dir').expand_path
               existing_dir.mkdir
               store = SimpleCommaStore.new(existing_dir)

               expect(store.path.to_s).to eq("#{ existing_dir }/#{ SimpleCommaStore::DEFAULT_FILE }")
            end

            # to encourage thread-safetey
            it 'should be frozen after init' do
               store = SimpleCommaStore.new

               expect(store).to be_frozen
            end
         end

         describe 'read' do
            let(:path) { Pathname.new(SimpleCommaStore::DEFAULT_FILE).expand_path }
            let(:store) { SimpleCommaStore.new(path) }

            before(:each) do
               contents = <<~CONTENTS
                  id, queue    , run_at,            initial_run_at,    expire_at,         attempts, last_fail_at,      last_error, data
                  1 , reminders, 2022-01-01T00:00Z, 2022-01-01T00:00Z, 2022-01-01T00:00Z, 5       , 2022-01-01T00:00Z, problem   , info
                  8 , reminders, 2022-01-01T00:00Z, 2022-01-01T00:00Z, 2022-01-01T00:00Z, 12      , 2022-01-01T00:00Z, asplode   , something
                  15, thumbs   , 2022-01-01T00:00Z, 2022-01-01T00:00Z, 2022-01-01T00:00Z, 19      , 2022-01-01T00:00Z, boom      , north means left
               CONTENTS

               path.write(contents)

               allow_any_instance_of(FakeFS::File).to receive(:flock)
            end

            it 'should read from a specific csv file' do
               data = '1, reminders, 2022-01-01T00:00:00Z, 2022-01-01T00:00:00Z, 2022-01-01T00:00:00Z, 5, 2022-01-01T00:00:00Z, problem, {user: 7}'

               [Pathname.new('special-procrastinator-data.csv'),
                Pathname.new('/some/place/some-other-data.csv')].each do |path|
                  path.dirname.mkpath
                  path.write <<~EXISTING
                     #{ SimpleCommaStore::HEADERS.join(',') }
                     #{ data }
                  EXISTING

                  store = SimpleCommaStore.new(path)

                  expect(store.read.length).to eq 1
               end
            end

            it 'should read the whole file' do
               expect(store.read.length).to eq 3
            end

            # this is needed to prevent reading files that are partially written. It might be possible to do a
            # write-tmp-and-swap instead, but it would need to be evaluated first vs multithreading and multiprocessing
            # (ie. multiple daemons)
            it 'should perform the read within a file transaction' do
               transaction = double('transaction')
               expect(FileTransaction).to receive(:new).with(path).and_return(transaction)
               expect(transaction).to receive(:read)

               store.read
            end

            it 'should handle a file with no tasks' do
               contents = <<~CONTENTS
                  id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
               CONTENTS

               path.write(contents)

               expect(store.read.length).to eq 0
            end

            it 'should handle a blank file' do
               path.write('')

               expect(store.read.length).to eq 0
            end

            context 'serializing JSON data column' do
               it 'should account for JSON object syntax' do
                  hash_data = JSON.dump(user: 7, hash: true)

                  contents = <<~CONTENTS
                     id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                     "1","","2022-01-01T00:00Z","2022-01-01T00:00Z","2022-01-01T00:00Z","5","2022-01-01T00:00Z","problem","#{ hash_data.gsub('"', '""') }"
                  CONTENTS

                  path.write(contents)

                  expect(store.read.first[:data]).to eq hash_data
               end

               it 'should account for JSON array syntax' do
                  array_data = JSON.dump([:this, 'is', :actually, 'an array'])

                  contents = <<~CONTENTS
                     id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                     "1","","2022-01-01T00:00Z","2022-01-01T00:00Z","2022-01-01T00:00Z","5","2022-01-01T00:00Z","problem","#{ array_data.gsub('"', '""') }"
                  CONTENTS

                  path.write(contents)

                  expect(store.read.first[:data]).to eq array_data
               end

               it 'should account for JSON string syntax' do
                  string_data = JSON.dump('this is a test string')

                  contents = <<~CONTENTS
                     id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                     "1","","2022-01-01T00:00Z","2022-01-01T00:00Z","2022-01-01T00:00Z","5","2022-01-01T00:00Z","problem","#{ string_data.gsub('"', '""') }"
                  CONTENTS

                  path.write(contents)

                  expect(store.read.first[:data]).to eq string_data
               end

               it 'should account for JSON integer syntax' do
                  integer_data = JSON.dump(5)

                  contents = <<~CONTENTS
                     id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                     "1","","2022-01-01T00:00Z","2022-01-01T00:00Z","2022-01-01T00:00Z","5","2022-01-01T00:00Z","problem","#{ integer_data }"
                  CONTENTS

                  path.write(contents)

                  expect(store.read.first[:data]).to eq integer_data
               end
            end

            it 'should account for CSV escaped strings' do
               str = 'string with "quotes" in it'

               # In CSV, double quotes are put twice in a row to escape them (so " becomes "").
               # The backslash is from JSON strings.
               # This HEREDOC must be non-interpolated or else you will lose 1 sanity point and be stunned for a turn.
               contents = <<~'CONTENTS'
                  id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                  "1","","2022-01-01T00:00Z","2022-01-01T00:00Z","2022-01-01T00:00Z","5","2022-01-01T00:00Z","problem","""string with \""quotes\"" in it"""
               CONTENTS

               path.write(contents)

               db = store.read

               data = JSON.dump(str)
               expect(db.first[:data]).to eq data
            end

            it 'should return hashes of the read data' do
               data = store.read

               data.each do |d|
                  expect(d).to be_a Hash
               end
            end

            it 'should ignore blank lines' do
               contents = <<~'CONTENTS'
                  id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                  "1","","2022-01-01T00:00Z","2022-01-01T00:00Z","2022-01-01T00:00Z","5","2022-01-01T00:00Z","problem","5"

                  "2","","2022-01-01T00:00Z","2022-01-01T00:00Z","","5","","","5"
               CONTENTS

               path.write(contents)

               expect(store.read.length).to eq 2
            end

            it 'should filter data by queue' do
               contents = <<~CONTENTS
                  id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                  "1","thumbnail","2022-01-01T00:00Z","2022-01-01T00:00Z","","5","","",""
                  "2","greetings","2022-01-01T00:00Z","2022-01-01T00:00Z","2022-01-01T00:00Z","5","","",""
                  "3","reminders","2022-01-01T00:00Z","2022-01-01T00:00Z","","5","2022-01-01T00:00Z","problem",""
                  "4","greetings","2022-01-01T00:00Z","2022-01-01T00:00Z","2022-01-01T00:00Z","5","","",""
               CONTENTS

               path.write(contents)

               data = store.read(queue: :greetings)

               expect(data.length).to eq 2
               expect(data.first).to include(queue: :greetings, id: 2)
               expect(data.last).to include(queue: :greetings, id: 4)
            end

            it 'should filter data by id' do
               data = store.read(id: 8)

               expect(data.length).to eq 1
               expect(data.first).to include(id: 8)
            end

            it 'should return all when filter is empty' do
               data = store.read

               expect(data.length).to eq 3
            end

            it 'should convert types' do
               contents = <<~CONTENTS
                  id, queue,   run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                  "1","emails","2022-01-01T00:00Z","2022-01-01T00:00Z","2022-01-01T00:00Z","0","","",""
                  "2","emails","2022-01-01T00:00Z","2022-01-01T00:00Z","","","","",""
                  "3","emails","","2022-01-01T00:00Z","","2","2022-01-01T00:00Z","problem",""
               CONTENTS

               path.write(contents)

               data = store.read

               time_keys = [:run_at, :initial_run_at, :expire_at, :last_fail_at]
               int_keys  = [:id, :attempts]

               data.each do |row|
                  time_keys.each do |key|
                     expect(row[key]).to satisfy do |value|
                        value.is_a?(Time) || value.nil?
                     end
                  end
                  int_keys.each do |key|
                     value = row[key]
                     expect(value).to be_an(Integer)
                  end
                  expect(row[:queue]).to be_a Symbol
                  expect(row[:last_error]).to be_a String
                  expect(row[:data]).to be_a String
               end
            end
         end

         describe 'create' do
            let(:path) { Pathname.new(SimpleCommaStore::DEFAULT_FILE).expand_path }
            let(:store) { SimpleCommaStore.new(path) }

            let(:required_args) do
               {queue: :some_queue, run_at: Time.at(0), expire_at: nil, data: ''}
            end

            before(:each) do
               allow_any_instance_of(FakeFS::File).to receive(:flock)
            end

            it 'should write a header row' do
               store.create(**required_args)

               file_content = path.readlines

               expected_header = 'id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data'

               expect(file_content.first&.strip).to eq expected_header
            end

            it 'should write a new data line' do
               store.create(**required_args)

               expect(path.readlines.length).to eq 2 # header row + 1 data row
            end

            it 'should write given values' do
               default_data = {run_at: nil, expire_at: nil}
               data         = [
                     {queue: :thumbnails, data: ''},
                     {queue: :reminders, data: 'user_id: 5'}
               ]

               data.each do |arguments|
                  store.create(**default_data.merge(arguments))

                  data_line = path.readlines.last&.strip

                  {
                        queue:          arguments[:queue],
                        run_at:         arguments[:run_at],
                        initial_run_at: arguments[:initial_run_at],
                        expire_at:      arguments[:expire_at],
                        data:           arguments[:data]
                  }.each_value do |expected_value|
                     expect(data_line).to include expected_value.to_s
                  end
               end
            end

            it 'should write time values in ISO 8601' do
               default_data = {queue: :reminders, run_at: nil, initial_run_at: nil, expire_at: nil}

               test_keys   = [:run_at, :initial_run_at, :expire_at]
               test_values = [Time.at(0), Time.at(10), nil]

               test_keys.each do |field|
                  test_values.each do |value|
                     store.create(**default_data.merge(field => value))

                     data_line = path.readlines.last&.strip

                     expect(data_line).to include(value&.iso8601 || '')
                  end
               end
            end

            it 'should write default values' do
               store.create(**required_args)

               data_line = path.readlines.last&.strip

               {
                     attempts:     '0',
                     last_fail_at: '',
                     last_error:   ''
               }.each_value do |expected_value|
                  expect(data_line).to include expected_value
               end
            end

            it 'should create a new id for the new task' do
               contents = <<~CONTENTS
                  id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                  "1","","2022-01-01T00:00Z","2022-01-01T00:00Z","","5","","",""
                  "2","","2022-01-01T00:00Z","2022-01-01T00:00Z","","5","","",""
                  "37","","2022-01-01T00:00Z","2022-01-01T00:00Z","","5","","",""
               CONTENTS

               path.write(contents)

               store.create(**required_args)

               file_content = path.readlines

               expect(file_content.last&.strip).to start_with('"38"')
            end

            it 'should keep existing content' do
               prior_content = <<~CONTENTS
                  id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data
                  "1","","2022-01-01T00:00:00Z","2022-01-01T01:00:00Z","2022-01-01T02:00:00Z","5","2022-01-01T03:00:00Z","err",""
                  "2","","2022-02-02T00:00:00Z","2022-02-02T01:00:00Z","","5","","",""
                  "37","","2022-03-03T00:00:00Z","2022-03-03T01:00:00Z","2022-03-03T02:00:00Z","5","2022-03-03T03:00:00Z","err",""
               CONTENTS

               path.write(prior_content)

               store.create(**required_args)

               file_content = path.read || ''

               expect(file_content.split("\n").size).to eq 5 # 1 header + 3 existing + 1 new record
               expect(file_content).to start_with(prior_content)
            end

            it 'should perform the create within a file transaction' do
               transaction = double('transaction')
               expect(FileTransaction).to receive(:new).with(path).and_return(transaction)
               expect(transaction).to receive(:write)

               store.create(**required_args)
            end
         end

         describe 'update' do
            let(:path) { Pathname.new('procrastinator-data.csv').expand_path }
            let(:store) { SimpleCommaStore.new(path) }

            before(:each) do
               path.write <<~CONTENTS
                  id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data
                  "1","reminders","2022-01-01T00:00Z","2022-01-01T00:00Z","","5","2022-01-01T00:00Z","err",""
                  "2","reminders","2022-01-01T00:00Z","2022-01-01T00:00Z","2022-01-01T00:00Z","10","2022-01-01T00:00Z","err",""
                  "37","thumbnails","2022-01-01T00:00Z","2022-01-01T00:00Z","","15","","","size: 500"
               CONTENTS

               allow_any_instance_of(FakeFS::File).to receive(:flock)
            end

            it 'should write the changed data to a file' do
               id = 2

               attempts = 14
               error    = 'everything is okay alarm'
               data     = 'boop'

               store.update(id,
                            attempts:   attempts,
                            last_error: error,
                            data:       data)

               file_lines = path.readlines.collect(&:chomp)

               line = [id.to_s,
                       'reminders',
                       '2022-01-01T00:00:00Z',
                       '2022-01-01T00:00:00Z',
                       '2022-01-01T00:00:00Z',
                       attempts.to_s,
                       '2022-01-01T00:00:00Z',
                       error,
                       data]

               expect(file_lines[2]).to eq line.collect { |v| %["#{ v }"] }.join(',')
            end

            it 'should convert time fields to iso8601' do
               id = 2

               run      = '2022-01-01T01:01:01-01:00'
               initial  = '2022-01-02T02:02:02-02:00'
               expire   = '2022-03-03T03:03:03-03:00'
               error_at = '2022-04-04T04:04:04-04:00'

               store.update(id,
                            run_at:         Time.parse(run),
                            initial_run_at: Time.parse(initial),
                            expire_at:      Time.parse(expire),
                            attempts:       10,
                            last_fail_at:   Time.parse(error_at),
                            last_error:     'err',
                            data:           '')

               file_lines = path.readlines.collect(&:chomp)

               line = [id.to_s,
                       'reminders',
                       run,
                       initial,
                       expire,
                       '10',
                       error_at,
                       'err',
                       '']

               expect(file_lines[2]).to eq line.collect { |v| %["#{ v }"] }.join(',')
            end

            it 'should NOT create a new task' do
               store.update(2, run_at: Time.at(0))

               file_lines = path.readlines

               expect(file_lines.size).to eq 4 # header + 3 data rows
            end

            it 'should NOT change the task id' do
               store.update(2, run_at: Time.at(0))

               file_lines = path.readlines

               expect(file_lines[0]).to start_with('id,')
               expect(file_lines[1]).to start_with('"1",')
               expect(file_lines[2]).to start_with('"2",')
               expect(file_lines[3]).to start_with('"37",')
            end

            it 'should perform the update within a file transaction' do
               transaction = double('transaction')
               expect(FileTransaction).to receive(:new).with(path).and_return(transaction)
               expect(transaction).to receive(:write)

               store.update(2, run_at: 0)
            end
         end

         describe 'delete' do
            let(:path) { Pathname.new('procrastinator-data.csv').expand_path }
            let(:store) { SimpleCommaStore.new(path) }

            before(:each) do
               path.write <<~CONTENTS
                  id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data
                  "1","reminders","2022-01-01T00:00Z","2022-01-01T00:00Z","","5","","",""
                  "2","reminders","2022-01-01T00:00Z","2022-01-01T00:00Z","","10","","",""
                  "37","thumbnails","2022-01-01T00:00Z","2022-01-01T00:00Z","","15","","","size: 500"
               CONTENTS

               allow_any_instance_of(FakeFS::File).to receive(:flock)
            end

            it 'should remove the task' do
               store.delete(2)

               expect(path.read).to eq <<~CONTENTS
                  id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data
                  "1","reminders","2022-01-01T00:00:00Z","2022-01-01T00:00:00Z","","5","","",""
                  "37","thumbnails","2022-01-01T00:00:00Z","2022-01-01T00:00:00Z","","15","","","size: 500"
               CONTENTS
            end

            it 'should perform the delete within a file transaction' do
               transaction = double('transaction')
               expect(FileTransaction).to receive(:new).with(path).and_return(transaction)
               expect(transaction).to receive(:write)

               store.delete(2)
            end
         end

         describe 'generate' do
            let(:store) { SimpleCommaStore.new }
            let(:path) { store.path }

            # CSV specification (RFC 4180) considers two dquotes in a row ("") as an escaped dquote (")
            it 'should escape double quote characters' do
               result = store.generate([{data: 'this has "quotes" in it'}])

               expect(result.strip).to end_with(',"this has ""quotes"" in it"')
            end

            it 'should force quote every field' do
               task_info = {
                     id:             1,
                     queue:          :reminders,
                     run_at:         Time.at(3),
                     initial_run_at: Time.at(4),
                     expire_at:      Time.at(5),
                     attempts:       0,
                     last_fail_at:   Time.at(7),
                     last_error:     '',
                     data:           'user_id: 5'
               }

               result = store.generate([task_info])

               new_row = task_info.values.collect { |x| %["#{ x }"] }.join(',')

               expect(result).to eq <<~CONTENT
                  id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data
                  #{ new_row }
               CONTENT
            end
         end
      end

      describe FileTransaction do
         # exclusive && nonblocking (ie. won't wait until success)
         let(:flock_mask) { File::LOCK_EX | File::LOCK_NB }

         let(:path) { Pathname.new 'procrastinator-data.csv' }

         describe 'initialize' do
            it 'should ensure the file exists' do
               FileTransaction.new(path)

               expect(path).to exist
            end
         end

         describe '#read' do
            let(:storage_path) { Pathname.new 'test-file.txt' }
            let(:transaction) { FileTransaction.new(storage_path) }

            before(:each) do
               allow_any_instance_of(FakeFS::File).to receive(:flock)
            end

            it 'should alias #transact' do
               block = proc do
                  # something
               end
               expect(transaction).to receive(:transact).with(writable: false, &block)

               transaction.read(&block)
            end
         end

         describe '#write' do
            let(:storage_path) { Pathname.new 'test-file.txt' }
            let(:transaction) { FileTransaction.new(storage_path) }

            it 'should call #transact with writable mode and block' do
               block = proc do
                  # something
               end
               expect(transaction).to receive(:transact).with(writable: true, &block)

               transaction.write(&block)
            end
         end

         describe '#transact' do
            let(:storage_path) { Pathname.new 'test-file.txt' }
            let(:transaction) { FileTransaction.new(storage_path) }

            it 'should return the block result' do
               [true, false].each do |mode|
                  allow_any_instance_of(FakeFS::File).to receive(:flock)

                  result = double('something')

                  expect(transaction.transact(writable: mode) do
                     result
                  end).to eq result
               end
            end

            context 'readable' do
               let(:storage_path) { Pathname.new 'test-file.txt' }
               let(:transaction) { FileTransaction.new(storage_path) }

               before(:each) do
                  allow_any_instance_of(FakeFS::File).to receive(:flock)
               end

               it 'should pass the current file contents to the block' do
                  content = nil
                  storage_path.write 'test content'
                  transaction.read do |current_content|
                     content = current_content
                  end

                  expect(content).to eq('test content')
               end

               it 'should NOT overwrite the existing file' do
                  orig = 'a' * 10
                  storage_path.write(orig)
                  transaction.read do
                     'zzz'
                  end

                  expect(storage_path.read).to eq orig
               end
            end

            context 'writable' do
               let(:storage_path) { Pathname.new 'test-file.txt' }
               let(:transaction) { FileTransaction.new(storage_path) }

               before(:each) do
                  allow_any_instance_of(FakeFS::File).to receive(:flock)
               end

               it 'should pass the current file contents to the block' do
                  content = nil
                  storage_path.write 'test content'
                  transaction.transact(writable: true) do |current_content|
                     content = current_content
                  end

                  expect(content).to eq('test content')
               end

               it 'should write the block result to the file' do
                  transaction.transact(writable: true) do
                     'test content'
                  end

                  expect(storage_path.read).to eq('test content')
               end

               it 'should overwrite the entire existing file' do
                  storage_path.write('a' * 10)
                  transaction.transact(writable: true) do
                     'zzz'
                  end

                  expect(storage_path.read).to eq('zzz')
               end
            end

            context 'thread safety' do
               let(:lock) { FileTransaction.file_mutex[storage_path.to_s] }

               before(:each) do
                  allow_any_instance_of(FakeFS::File).to receive(:flock)
               end

               it 'should reserve the file before yielding' do
                  transaction.transact do
                     expect(lock).to be_locked
                  end
               end

               it 'should release the mutex after normal completion' do
                  transaction.transact do
                     # ... do stuff ...
                  end

                  expect(lock).to_not be_locked
               end

               it 'should release the mutex after error' do
                  expect do
                     transaction.transact do
                        raise 'stomachache'
                     end
                  end.to raise_error RuntimeError, 'stomachache'

                  expect(lock).to_not be_locked
               end
            end

            # multiprocess file lock safety
            context 'multiprocess' do
               let(:tmp_dir) { Pathname.new Dir.mktmpdir('procrastinator-test') }
               let(:storage_path) { tmp_dir / 'some-file.txt' }

               before(:each) do
                  # FakeFS doesn't currently support file locks
                  FakeFS.deactivate!

                  storage_path.write ''
               end

               after(:each) do
                  Pathname.new(storage_path).open.flock(File::LOCK_UN)
                  FileUtils.remove_entry(tmp_dir)
                  FakeFS.activate!
               end

               it 'should flock the file before reading' do
                  transaction.transact do
                     expect(storage_path.open.flock(flock_mask)).to(eq(false),
                                                                    "expected #{ storage_path } to be locked")
                  end
               end

               it 'should flock the file before writing' do
                  transaction.transact(writable: true) do
                     expect(storage_path.open.flock(flock_mask)).to(eq(false),
                                                                    "expected #{ storage_path } to be locked")
                  end
               end

               it 'should unflock the file when done' do
                  transaction.transact do
                     # ... do stuff ...
                  end

                  expect(storage_path.open.flock(flock_mask)).to(eq(0),
                                                                 "expected #{ storage_path } to be unlocked")
               end

               it 'should unflock the file when errored' do
                  expect do
                     transaction.transact do
                        raise 'vexed'
                     end
                  end.to raise_error RuntimeError, 'vexed'

                  expect(storage_path.open.flock(flock_mask)).to(eq(0),
                                                                 "expected #{ storage_path } to be unlocked")
               end
            end
         end
      end
   end
end
