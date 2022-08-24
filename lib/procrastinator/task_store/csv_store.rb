# frozen_string_literal: true

require 'csv'
require 'pathname'

module Procrastinator
   module TaskStore
      # Simple Task I/O object that writes task information (ie. TaskMetaData attributes) to a CSV file.
      #
      # @author Robin Miller
      class CSVStore
         # ordered
         HEADERS = [:id, :queue, :run_at, :initial_run_at, :expire_at,
                    :attempts, :last_fail_at, :last_error, :data].freeze

         DEFAULT_FILE = Pathname.new('procrastinator-tasks.csv').freeze

         CONVERTER = proc do |value, field_info|
            if field_info.header == :data
               value
            else
               begin
                  Integer(value)
               rescue ArgumentError
                  value
               end
            end
         end

         attr_reader :path

         def initialize(file_path = DEFAULT_FILE)
            @path = Pathname.new(file_path)

            if @path.directory? || @path.to_s.end_with?('/')
               @path /= DEFAULT_FILE
            elsif @path.extname.empty?
               @path = Pathname.new("#{ file_path }.csv")
            end
         end

         def read(filter = {})
            ensure_file

            data = CSV.parse(@path.read,
                             headers:           true,
                             header_converters: :symbol,
                             skip_blanks:       true,
                             converters:        CONVERTER,
                             force_quotes:      true).to_a

            headers = data.shift || HEADERS

            data = data.collect do |d|
               headers.zip(d).to_h
            end

            correct_types(data).select do |row|
               filter.keys.all? do |key|
                  row[key] == filter[key]
               end
            end
         end

         def create(queue:, run_at:, initial_run_at:, expire_at:, data: '')
            existing_data = read

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
            existing_data = read

            task_data = existing_data.find do |task|
               task[:id] == id
            end

            task_data&.merge!(data)

            write(existing_data)
         end

         def delete(id)
            existing_data = read

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

         private

         def ensure_file
            return if @path.exist?

            @path.dirname.mkpath
            FileUtils.touch(@path)
         end

         def correct_types(data)
            non_empty_keys = [:run_at, :expire_at, :attempts, :last_fail_at]

            data.collect do |hash|
               non_empty_keys.each do |key|
                  hash.delete(key) if hash[key].is_a?(String) && hash[key].empty?
               end

               hash[:attempts] ||= 0

               # hash[:data]  = (hash[:data] || '').gsub('""', '"')
               hash[:queue] = hash[:queue].to_sym

               hash
            end
         end
      end
   end
end
