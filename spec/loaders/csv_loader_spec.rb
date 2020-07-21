# frozen_string_literal: true

require 'spec_helper'
require 'pathname'

module Procrastinator
   module Loader
      describe CSVLoader do
         describe 'initialize' do
            include FakeFS::SpecHelpers

            it 'should accept a path argument' do
               CSVLoader.new('testfile.csv').write([])

               expect(File).to exist('testfile.csv')
            end

            it 'should provide a default path argument' do
               CSVLoader.new.write([])

               expect(File).to exist(CSVLoader::DEFAULT_FILE)
            end

            it 'should add a .csv extension to the path if missing extension' do
               CSVLoader.new('plainfile').write([])

               expect(File).to exist('plainfile.csv')
            end

            it 'should add a default filename if the provided path is a directory name' do
               slash_end_path = '/some/place/'

               CSVLoader.new(slash_end_path).write([])

               expect(File).to exist("#{ slash_end_path }/#{ CSVLoader::DEFAULT_FILE }")
            end

            it 'should add a default filename if the provided path is an existing directory' do
               existing_dir = 'test_dir'
               FileUtils.mkdir existing_dir
               CSVLoader.new(existing_dir).write([])

               expect(File).to exist("#{ existing_dir }/#{ CSVLoader::DEFAULT_FILE }")
            end
         end

         describe 'read' do
            include FakeFS::SpecHelpers

            let(:path) { 'procrastinator-data.csv' }
            let(:loader) { CSVLoader.new(path) }

            before(:each) do
               contents = <<~CONTENTS
                  id, queue    , run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                  1 , reminders, 2     , 3             ,  4       , 5       , 6           , problem   , info
                  8 , reminders, 9     , 10            ,  11      , 12      , 13          , asplode   , something
                  15, thumbs   , 16    , 17            ,  18      , 19      , 20          , boom      , north means left
               CONTENTS

               File.open(path.to_s, 'w') do |f|
                  f.write(contents)
               end
            end

            it 'should read from a specific csv file' do
               data = '1, reminders, 2, 3, 4, 5, 6, problem, {user: 7}'

               [Pathname.new('special-procrastinator-data.csv'),
                Pathname.new('/some/place/some-other-data.csv')].each do |path|
                  path.dirname.mkpath
                  File.open(path.to_s, 'w') do |f|
                     f.puts(CSVLoader::HEADERS.join(','))
                     f.puts(data)
                  end

                  loader = CSVLoader.new(path)

                  expect(loader.read.length).to eq 1
               end
            end

            it 'should read the whole file' do
               expect(loader.read.length).to eq 3
            end

            it 'should account for YAML syntax' do
               first_data  = YAML.dump(user: 7, hash: true)
               second_data = YAML.dump('string data')
               third_data  = YAML.dump([:this, 'is', :an, 'array'])

               contents = <<~CONTENTS
                  id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                  "1","","2","3","4","5","6","problem","#{ first_data }"
                  "1","","2","3","4","5","6","problem","#{ second_data }"
                  "1","","2","3","4","5","6","problem","#{ third_data }"
               CONTENTS

               File.open(path.to_s, 'w') do |f|
                  f.write(contents)
               end

               db = loader.read

               expect(db[0][:data]).to eq first_data
               expect(db[1][:data]).to eq second_data
               expect(db[2][:data]).to eq third_data
            end

            it 'should account for CSV escaped strings' do
               data = YAML.dump('string with "quotes" in it')

               contents = <<~CONTENTS
                  id, queue, run_at, initial_run_at, expire_at, attempts, last_fail_at, last_error, data
                  "1","","2","3","4","5","6","problem","#{ data.gsub('"', '"""') }"
               CONTENTS

               File.open(path.to_s, 'w') do |f|
                  f.write(contents)
               end

               db = loader.read

               expect(db.first[:data]).to eq data
            end

            it 'should return hashes of the read data' do
               data = loader.read

               data.each do |d|
                  expect(d).to be_a Hash
               end
            end
         end

         describe 'create' do
            include FakeFS::SpecHelpers

            let(:path) { 'procrastinator-data.csv' }
            let(:loader) { CSVLoader.new(path) }

            let(:required_args) do
               {queue: :some_queue, run_at: 0, initial_run_at: 0, expire_at: nil, data: ''}
            end

            it 'should write a header row' do
               loader.create(required_args)

               file_content = File.new(path).readlines

               expected_header = 'id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data'

               expect(file_content.first.strip).to eq expected_header
            end

            it 'should write a new data line' do
               loader.create(required_args)

               file_content = File.new(path).readlines

               expect(file_content.length).to eq 2 # header row and data row
            end

            it 'should write given values' do
               data = [
                     {queue: :thumbnails, run_at: 0, initial_run_at: 1, expire_at: nil, data: ''},
                     {queue: :reminders, run_at: 3, initial_run_at: 4, expire_at: 5, data: 'user_id: 5'}
               ]

               data.each do |arguments|
                  loader.create(arguments)

                  file_content = File.new(path).readlines
                  data_line    = file_content.last.strip

                  {
                        queue:          arguments[:queue],
                        run_at:         arguments[:run_at],
                        initial_run_at: arguments[:initial_run_at],
                        expire_at:      arguments[:expire_at],
                        data:           arguments[:data],
                  }.values.each do |expected_value|
                     expect(data_line).to include expected_value.to_s
                  end
               end
            end

            it 'should write default values' do
               loader.create(required_args)

               file_content = File.new(path).readlines
               data_line    = file_content.last.strip

               {
                     attempts:     '0',
                     last_fail_at: '',
                     last_error:   '',
               }.values.each do |expected_value|
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

               File.open(path.to_s, 'w') do |f|
                  f.write(contents)
               end

               loader.create(required_args)

               file_content = File.new(path).readlines

               expect(file_content.last.strip).to start_with(%q["38",])
            end

            it 'should keep existing content' do
               contents = <<~CONTENTS
                  id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data
                  "1","","2","3","4","5","6","err",""
                  "2","","2","3","4","5","6","err",""
                  "37","","2","3","4","5","6","err",""
               CONTENTS

               File.open(path.to_s, 'w') do |f|
                  f.write(contents)
               end

               loader.create(required_args)

               file_content = File.new(path).read

               expect(file_content.split("\n").size).to eq 5 # header + 3 existing + new record
               expect(file_content).to start_with(contents)
            end
         end

         describe 'update' do
            include FakeFS::SpecHelpers

            let(:path) { 'procrastinator-data.csv' }
            let(:loader) { CSVLoader.new(path) }

            before(:each) do
               contents = <<~CONTENTS
                  id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data
                  "1","reminders","2","3","4","5","6","err",""
                  "2","reminders","7","8","9","10","11","err",""
                  "37","thumbnails","12","13","14","15","16","err","size: 500"
               CONTENTS

               File.open(path.to_s, 'w') do |f|
                  f.write(contents)
               end
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

               loader.update(id,
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
               loader.update(2, run_at: 0)

               file_lines = File.new(path).readlines

               expect(file_lines.size).to eq 4 # header + 3 data rows
            end

            it 'should NOT change the task id' do
               loader.update(2, run_at: 0)

               file_lines = File.new(path).readlines

               starts = %w[id,
                           "1",
                           "2",
                           "37",]

               file_lines.each_with_index do |line, i|
                  expect(line).to start_with starts[i]
               end
            end
         end

         describe 'delete' do
            include FakeFS::SpecHelpers

            let(:path) { 'procrastinator-data.csv' }
            let(:loader) { CSVLoader.new(path) }

            before(:each) do
               contents = <<~CONTENTS
                  id,queue,run_at,initial_run_at,expire_at,attempts,last_fail_at,last_error,data
                  "1","reminders","2","3","4","5","6","err",""
                  "2","reminders","7","8","9","10","11","err",""
                  "37","thumbnails","12","13","14","15","16","err","size: 500"
               CONTENTS

               File.open(path.to_s, 'w') do |f|
                  f.write(contents)
               end
            end

            it 'should remove a line' do
               id = 2

               loader.delete(id)

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

               loader.delete(id)

               file_content = File.new(path).read

               expect(file_content).to eq contents # header + 2 data rows
            end
         end

         describe 'write' do
            include FakeFS::SpecHelpers

            let(:path) { 'procrastinator-data.csv' }
            let(:loader) { CSVLoader.new(path) }

            it 'should create a file if it does not exist' do
               %w[missing-file.csv
                  /some/other/place/data-file.csv].each do |path|
                  loader = CSVLoader.new(path)

                  loader.write([])

                  expect(File).to exist(path)
               end
            end

            # CSV considers "" to an escaped "
            it 'should escape double quote characters' do
               loader.write([{data: 'this has "quotes" in it'}])

               file_content = File.new(path).readlines

               expect(file_content.last.strip).to end_with %q[,"this has ""quotes"" in it"]
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

               loader.write([task_info])

               file_content = File.new(path).readlines

               new_row = task_info.values.collect { |x| %["#{ x }"] }.join(',')

               expect(file_content.last.strip).to eq new_row
            end
         end
      end
   end
end
