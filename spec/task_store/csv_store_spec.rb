# frozen_string_literal: true

require 'spec_helper'
require 'pathname'

module Procrastinator
   module TaskStore
      describe CSVStore do
         describe 'initialize' do
            it 'should accept a path argument' do
               CSVStore.new('testfile.csv').write([])

               expect(File).to exist('testfile.csv')
            end

            it 'should provide a default path argument' do
               CSVStore.new.write([])

               expect(File).to exist(CSVStore::DEFAULT_FILE)
            end

            it 'should add a .csv extension to the path if missing extension' do
               CSVStore.new('plainfile').write([])

               expect(File).to exist('plainfile.csv')
            end

            it 'should add a default filename if the provided path is a directory name' do
               slash_end_path = '/some/place/'

               CSVStore.new(slash_end_path).write([])

               expect(File).to exist("#{ slash_end_path }/#{ CSVStore::DEFAULT_FILE }")
            end

            it 'should add a default filename if the provided path is an existing directory' do
               existing_dir = 'test_dir'
               FileUtils.mkdir existing_dir
               store = CSVStore.new(existing_dir)

               expect(store.path.to_s).to eq("#{ existing_dir }/#{ CSVStore::DEFAULT_FILE }")
            end

            it 'should ensure the file exists' do
               path = Pathname.new('test_dir/something.csv')
               CSVStore.new(path)

               expect(path).to exist
            end
         end

         describe 'read' do
            let(:path) { Pathname.new 'procrastinator-data.csv' }
            let(:store) { CSVStore.new(path) }

            before(:each) do
               contents = <<~CONTENTS
                  id, queue    , run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                  1 , reminders, 2     , 3             ,  4       , 5       , 6           , problem   , info
                  8 , reminders, 9     , 10            ,  11      , 12      , 13          , asplode   , something
                  15, thumbs   , 16    , 17            ,  18      , 19      , 20          , boom      , north means left
               CONTENTS

               path.write(contents)
            end

            it 'should read from a specific csv file' do
               data = '1, reminders, 2, 3, 4, 5, 6, problem, {user: 7}'

               [Pathname.new('special-procrastinator-data.csv'),
                Pathname.new('/some/place/some-other-data.csv')].each do |path|
                  path.dirname.mkpath
                  File.open(path.to_s, 'w') do |f|
                     f.puts(CSVStore::HEADERS.join(','))
                     f.puts(data)
                  end

                  store = CSVStore.new(path)

                  expect(store.read.length).to eq 1
               end
            end

            it 'should read the whole file' do
               expect(store.read.length).to eq 3
            end

            it 'should handle a file with no tasks' do
               contents = <<~CONTENTS
                  id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
               CONTENTS

               path.write(contents)

               expect(store.read.length).to eq 0
            end

            it 'should account for JSON syntax' do
               first_data  = JSON.dump(user: 7, hash: true)
               second_data = JSON.dump('string data')
               third_data  = JSON.dump([:this, 'is', :an, 'array'])

               contents = <<~CONTENTS
                  id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                  "1","","2","3","4","5","6","problem","#{ first_data.gsub('"', '""') }"
                  "1","","2","3","4","5","6","problem","#{ second_data.gsub('"', '""') }"
                  "1","","2","3","4","5","6","problem","#{ third_data.gsub('"', '""') }"
               CONTENTS

               path.write(contents)

               db = store.read

               expect(db[0][:data]).to eq first_data
               expect(db[1][:data]).to eq second_data
               expect(db[2][:data]).to eq third_data
            end

            it 'should account for CSV escaped strings' do
               str = 'string with "quotes" in it'

               # In CSV, double quotes are put twice in a row to escape them (so " becomes "").
               # The backslash is from JSON strings.
               # This HEREDOC must be non-interpolated or else you will lose 1 sanity point and be stunned for a turn.
               contents = <<~'CONTENTS'
                  id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                  "1","","2","3","4","5","6","problem","""string with \""quotes\"" in it"""
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

            it 'should filter data by queue' do
               contents = <<~CONTENTS
                  id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                  "1","thumbnail","2","3","4","5","6","problem",""
                  "2","greetings","2","3","4","5","6","problem",""
                  "3","reminders","2","3","4","5","6","problem",""
                  "4","greetings","2","3","4","5","6","problem",""
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
                  "1","emails","1","1","4","0","","",""
                  "2","emails","2","2","4","","","",""
                  "3","emails","","3","","2","2","problem",""
               CONTENTS

               path.write(contents)

               data = store.read

               nil_int_keys = [:run_at, :expire_at, :last_fail_at]
               int_keys     = [:id, :initial_run_at, :attempts]

               data.each do |row|
                  nil_int_keys.each do |key|
                     expect(row[key]).to satisfy do |value|
                        value.is_a?(Integer) || value.nil?
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
            let(:path) { 'procrastinator-data.csv' }
            let(:store) { CSVStore.new(path) }

            let(:required_args) do
               {queue: :some_queue, run_at: 0, initial_run_at: 0, expire_at: nil, data: ''}
            end

            it 'should write a header row' do
               store.create(required_args)

               file_content = File.new(path).readlines

               expected_header = 'id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data'

               expect(file_content.first&.strip).to eq expected_header
            end

            it 'should write a new data line' do
               store.create(required_args)

               file_content = File.new(path).readlines

               expect(file_content.length).to eq 2 # header row and data row
            end

            it 'should write given values' do
               data = [
                     {queue: :thumbnails, run_at: 0, initial_run_at: 1, expire_at: nil, data: ''},
                     {queue: :reminders, run_at: 3, initial_run_at: 4, expire_at: 5, data: 'user_id: 5'}
               ]

               data.each do |arguments|
                  store.create(arguments)

                  file_content = File.new(path).readlines
                  data_line    = file_content.last&.strip

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

            it 'should write default values' do
               store.create(required_args)

               file_content = File.new(path).readlines
               data_line    = file_content.last&.strip

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
                  "1","","2","3","4","5","6","err",""
                  "2","","2","3","4","5","6","err",""
                  "37","","2","3","4","5","6","err",""
               CONTENTS

               File.write(path, contents)

               store.create(required_args)

               file_content = File.new(path).readlines

               expect(file_content.last&.strip).to start_with('"38"')
            end

            it 'should keep existing content' do
               contents = <<~CONTENTS
                  id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data
                  "1","","2","3","4","5","6","err",""
                  "2","","2","3","4","5","6","err",""
                  "37","","2","3","4","5","6","err",""
               CONTENTS

               File.write(path, contents)

               store.create(required_args)

               file_content = File.new(path).read || ''

               expect(file_content.split("\n").size).to eq 5 # header + 3 existing + new record
               expect(file_content).to start_with(contents)
            end
         end

         describe 'update' do
            let(:path) { 'procrastinator-data.csv' }
            let(:store) { CSVStore.new(path) }

            before(:each) do
               contents = <<~CONTENTS
                  id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data
                  "1","reminders","2","3","4","5","6","err",""
                  "2","reminders","7","8","9","10","11","err",""
                  "37","thumbnails","12","13","14","15","16","err","size: 500"
               CONTENTS

               File.write(path, contents)
            end

            it 'should write the changed data to a file' do
               id = 2

               run      = 0
               initial  = 0
               expire   = 0
               attempts = 14
               error    = 'everything is okay alarm'
               error_at = 0
               data     = 'boop'

               store.update(id,
                            run_at:         run,
                            initial_run_at: initial,
                            expire_at:      expire,
                            attempts:       attempts,
                            last_fail_at:   error_at,
                            last_error:     error,
                            data:           data)

               file_lines = File.new(path).readlines

               line = %["#{ id }","reminders","#{ run }","#{ initial }","#{ expire }","#{ attempts }","#{ error_at }","#{ error }","#{ data }"\n]

               expect(file_lines[2]).to eq line
            end

            it 'should NOT create a new task' do
               store.update(2, run_at: 0)

               file_lines = File.new(path).readlines

               expect(file_lines.size).to eq 4 # header + 3 data rows
            end

            it 'should NOT change the task id' do
               store.update(2, run_at: 0)

               file_lines = File.new(path).readlines

               expect(file_lines[0]).to start_with('id,')
               expect(file_lines[1]).to start_with('"1",')
               expect(file_lines[2]).to start_with('"2",')
               expect(file_lines[3]).to start_with('"37",')
            end
         end

         describe 'delete' do
            let(:path) { 'procrastinator-data.csv' }
            let(:store) { CSVStore.new(path) }

            before(:each) do
               contents = <<~CONTENTS
                  id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data
                  "1","reminders","2","3","4","5","6","err",""
                  "2","reminders","7","8","9","10","11","err",""
                  "37","thumbnails","12","13","14","15","16","err","size: 500"
               CONTENTS

               File.write(path, contents)
            end

            it 'should remove a line' do
               id = 2

               store.delete(id)

               file_lines = File.new(path).readlines

               expect(file_lines.size).to eq 3 # header + 2 data rows
            end

            it 'should remove the task' do
               contents = <<~CONTENTS
                  id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data
                  "1","reminders","2","3","4","5","6","err",""
                  "37","thumbnails","12","13","14","15","16","err","size: 500"
               CONTENTS

               id = 2

               store.delete(id)

               file_content = File.new(path).read

               expect(file_content).to eq contents # header + 2 data rows
            end
         end

         describe 'write' do
            let(:path) { 'procrastinator-data.csv' }
            let(:store) { CSVStore.new(path) }

            it 'should create a file if it does not exist' do
               %w[missing-file.csv
                  /some/other/place/data-file.csv].each do |path|
                  store = CSVStore.new(path)

                  store.write([])

                  expect(File).to exist(path)
               end
            end

            # CSV considers "" to an escaped "
            it 'should escape double quote characters' do
               store.write([{data: 'this has "quotes" in it'}])

               file_content = File.new(path).readlines

               expect(file_content.last&.strip).to end_with(',"this has ""quotes"" in it"')
            end

            it 'should force quote every field' do
               task_info = {
                     id:             1,
                     queue:          :reminders,
                     run_at:         3,
                     initial_run_at: 4,
                     expire_at:      5,
                     attempts:       0,
                     last_fail_at:   '',
                     last_error:     '',
                     data:           'user_id: 5'
               }

               store.write([task_info])

               file_content = File.new(path).readlines

               new_row = task_info.values.collect { |x| %["#{ x }"] }.join(',')

               expect(file_content.last&.strip).to eq new_row
            end
         end
      end
   end
end
