# frozen_string_literal: true

require 'csv'
require 'pathname'

module Procrastinator
   module Loader
      # Simple Task I/O object that writes task information (ie. TaskMetaData attributes) to a CSV file.
      #
      # @author Robin Miller
      class CSVLoader
         # ordered
         HEADERS = [:id, :queue, :run_at, :initial_run_at, :expire_at,
                    :attempts, :last_fail_at, :last_error, :data].freeze

         DEFAULT_FILE = 'procrastinator-tasks.csv'

         def initialize(file_path = DEFAULT_FILE)
            @path = Pathname.new(file_path)

            if @path.directory? || @path.to_s.end_with?('/')
               @path += DEFAULT_FILE
            elsif @path.extname.empty?
               @path = Pathname.new("#{ file_path }.csv")
            end
         end

         def read(filter = {})
            data = CSV.table(@path.to_s, force_quotes: false).to_a

            headers = data.shift

            data = data.collect do |d|
               hash = headers&.zip(d).to_h

               hash[:data]  = hash[:data].gsub('""', '"')
               hash[:queue] = hash[:queue].to_sym

               hash
            end

            data.select do |row|
               filter.keys.all? do |key|
                  row[key] == filter[key]
               end
            end
         end

         def create(queue:, run_at:, initial_run_at:, expire_at:, data: '')
            existing_data = begin
                               read
                            rescue Errno::ENOENT
                               []
                            end

            max_id = existing_data.collect { |task| task[:id] }.max || 0

            new_data = {
                  id:             max_id + 1,
                  queue:          queue,
                  run_at:         run_at,
                  initial_run_at: initial_run_at,
                  expire_at:      expire_at,
                  attempts:       0,
                  data:           data
            }

            write(existing_data + [new_data])
         end

         def update(id, data)
            existing_data = begin
                               read
                            rescue Errno::ENOENT
                               []
                            end

            task_data = existing_data.find do |task|
               task[:id] == id
            end

            task_data&.merge!(data)

            write(existing_data)
         end

         def delete(id)
            existing_data = begin
                               read
                            rescue Errno::ENOENT
                               []
                            end

            existing_data.delete_if do |task|
               task[:id] == id
            end

            write(existing_data)
         end

         def write(data)
            lines = data.collect do |d|
               CSV.generate_line(d, headers: HEADERS, force_quotes: true)
            end

            @path.dirname.mkpath
            @path.open('w') do |f|
               f.puts HEADERS.join(',')
               f.puts lines.join
            end
         end
      end
   end
end
