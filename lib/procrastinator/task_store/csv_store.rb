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
         @file_transactors = {}

         class << self
            attr_reader :file_transactors
         end

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
            CSVStore.file_transactors[file_path.to_s] ||= Mutex.new

            @path = Pathname.new(file_path)

            if @path.directory? || @path.to_s.end_with?('/')
               @path /= DEFAULT_FILE
            elsif @path.extname.empty?
               @path = Pathname.new("#{ file_path }.csv")
            end

            freeze
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
            file_transaction do
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
         end

         def update(id, data)
            file_transaction do
               existing_data = read

               task_data = existing_data.find do |task|
                  task[:id] == id
               end

               task_data&.merge!(data)

               write(existing_data)
            end
         end

         def delete(id)
            file_transaction do
               existing_data = read

               existing_data.delete_if do |task|
                  task[:id] == id
               end

               write(existing_data)
            end
         end

         def write(data)
            lines = data.collect do |d|
               CSV.generate_line(d, headers: HEADERS, force_quotes: true).strip
            end

            lines.unshift(HEADERS.join(','))

            @path.dirname.mkpath
            @path.write lines.join("\n") << "\n"
         end

         private

         # Completes the given block as an atomic transaction locked using a global mutex table.
         #
         # The general idea is that there may be two threads that need to do these actions on the same file:
         #    thread A:   read
         #    thread B:   read
         #    thread A/B: write
         #    thread A/B: write
         #
         # When this sequence happens, the second file write is based on old information and loses the info from
         # the prior write. Using a global mutex per file path prevents this case.
         def file_transaction(&block)
            semaphore = CSVStore.file_transactors[@path.to_s]
            semaphore.synchronize(&block)
         end

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
