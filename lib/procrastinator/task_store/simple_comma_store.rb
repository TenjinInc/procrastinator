# frozen_string_literal: true

require 'csv'
require 'pathname'

module Procrastinator
   # Task storage strategies.
   #
   # All task stores must implement the API #read, #create, #update, #delete.
   module TaskStore
      # Simple Task I/O adapter that writes task information (ie. TaskMetaData attributes) to a CSV file.
      #
      # SimpleCommaStore is not designed for efficiency or large loads (10,000+ tasks). For critical production
      # environments, it is strongly recommended to use a more robust storage mechanism like a proper database.
      #
      # @author Robin Miller
      class SimpleCommaStore
         # Ordered list of CSV column headers
         HEADERS = [:id, :queue, :run_at, :initial_run_at, :expire_at,
                    :attempts, :last_fail_at, :last_error, :data].freeze

         # Columns that store time information
         TIME_FIELDS = [:run_at, :initial_run_at, :expire_at, :last_fail_at].freeze

         # CSV file extension
         EXT = 'csv'

         # Default filename
         DEFAULT_FILE = Pathname.new("procrastinator-tasks.#{ EXT }").freeze

         # CSV Converter lambda
         #
         # @see CSV
         READ_CONVERTER = proc do |value, field_info|
            if field_info.header == :data
               value
            elsif TIME_FIELDS.include? field_info.header
               value.empty? ? nil : Time.parse(value)
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
               @path = @path.dirname / "#{ @path.basename }.csv"
            end

            @path = @path.expand_path

            freeze
         end

         # Parses the CSV file for data matching the given filter, or all if no filter provided.
         #
         # @param filter [Hash] Specified attributes to match.
         # @return [Array<Hash>]
         def read(filter = {})
            CSVFileTransaction.new(@path).read do |existing_data|
               existing_data.select do |row|
                  filter.keys.all? do |key|
                     row[key] == filter[key]
                  end
               end
            end
         end

         # Saves a task to the CSV file.
         #
         # @param queue [String] queue name
         # @param run_at [Time, nil] time to run the task at
         # @param initial_run_at [Time, nil] first time to run the task at. Defaults to run_at.
         # @param expire_at [Time, nil] time to expire the task
         def create(queue:, run_at:, expire_at: nil, data: '', initial_run_at: nil)
            CSVFileTransaction.new(@path).write do |tasks|
               max_id = tasks.collect { |task| task[:id] }.max || 0

               new_data = {
                     id:             max_id + 1,
                     queue:          queue,
                     run_at:         run_at,
                     initial_run_at: initial_run_at || run_at,
                     expire_at:      expire_at,
                     attempts:       0,
                     data:           data
               }

               generate(tasks + [new_data])
            end
         end

         # Updates an existing task in the CSV file.
         #
         # @param id [Integer] task ID number
         # @param data [Hash] new data to save
         def update(id, data)
            CSVFileTransaction.new(@path).write do |tasks|
               task_data = tasks.find do |task|
                  task[:id] == id
               end

               task_data&.merge!(data)

               generate(tasks)
            end
         end

         # Removes an existing task from the CSV file.
         #
         # @param id [Integer] task ID number
         def delete(id)
            CSVFileTransaction.new(@path).write do |existing_data|
               generate(existing_data.reject { |task| task[:id] == id })
            end
         end

         # Generates a CSV string from the given data.
         #
         # @param data [Array] list of data to convert into CSV
         # @return [String] Generated CSV string
         def generate(data)
            lines = data.collect do |d|
               TIME_FIELDS.each do |field|
                  d[field] = d[field]&.iso8601
               end
               CSV.generate_line(d, headers: HEADERS, force_quotes: true).strip
            end

            lines.unshift(HEADERS.join(','))

            lines.join("\n") << "\n"
         end

         # Adds CSV parsing to the file reading
         class CSVFileTransaction < FileTransaction
            # (see FileTransaction#transact)
            def transact(writable: nil)
               super(writable: writable) do |file_str|
                  yield(parse(file_str))
               end
            end

            private

            def parse(csv_string)
               data = CSV.parse(csv_string,
                                headers:     true, header_converters: :symbol,
                                skip_blanks: true, converters: READ_CONVERTER, force_quotes: true).to_a

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
end
