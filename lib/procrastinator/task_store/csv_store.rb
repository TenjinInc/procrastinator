# frozen_string_literal: true

require 'csv'
require 'pathname'

module Procrastinator
   module TaskStore
      # Simple Task I/O adapter that writes task information (ie. TaskMetaData attributes) to a CSV file.
      #
      # CSVStore is not designed for efficiency or large loads (10,000+ tasks).
      #
      # For critical production environments, it is strongly recommended to use a more robust storage mechanism like a
      # proper database.
      #
      # @author Robin Miller
      class CSVStore
         # ordered
         HEADERS = [:id, :queue, :run_at, :initial_run_at, :expire_at,
                    :attempts, :last_fail_at, :last_error, :data].freeze

         EXT          = 'csv'
         DEFAULT_FILE = Pathname.new("procrastinator-tasks.#{ EXT }").freeze

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

            freeze
         end

         def read(filter = {})
            parse(@path.read).select do |row|
               filter.keys.all? do |key|
                  row[key] == filter[key]
               end
            end
         end

         def create(queue:, run_at:, initial_run_at:, expire_at:, data: '')
            FileTransaction.new(@path) do |existing_data|
               tasks  = parse(existing_data)
               max_id = tasks.collect { |task| task[:id] }.max || 0

               new_data = {
                     id:             max_id + 1,
                     queue:          queue,
                     run_at:         run_at,
                     initial_run_at: initial_run_at,
                     expire_at:      expire_at,
                     attempts:       0,
                     data:           data
               }

               generate(tasks + [new_data])
            end
         end

         def update(id, data)
            FileTransaction.new(@path) do |existing_data|
               tasks     = parse(existing_data)
               task_data = tasks.find do |task|
                  task[:id] == id
               end

               task_data&.merge!(data)
               generate(tasks)
            end
         end

         def delete(id)
            FileTransaction.new(@path) do |file_content|
               existing_data = parse(file_content)
               generate(existing_data.reject { |task| task[:id] == id })
            end
         end

         def generate(data)
            lines = data.collect do |d|
               CSV.generate_line(d, headers: HEADERS, force_quotes: true).strip
            end

            lines.unshift(HEADERS.join(','))

            lines.join("\n") << "\n"
         end

         private

         def parse(csv_string)
            data = CSV.parse(csv_string,
                             headers:           true,
                             header_converters: :symbol,
                             skip_blanks:       true,
                             converters:        CONVERTER,
                             force_quotes:      true).to_a

            headers = data.shift || HEADERS

            data = data.collect do |d|
               headers.zip(d).to_h
            end

            correct_types(data)
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
