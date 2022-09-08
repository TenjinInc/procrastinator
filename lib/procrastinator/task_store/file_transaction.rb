# frozen_string_literal: true

require 'pathname'

module Procrastinator
   module TaskStore
      # The general idea is that there may be two threads that need to do these actions on the same file:
      #    thread A:   read
      #    thread B:   read
      #    thread A/B: write
      #    thread A/B: write
      #
      # When this sequence happens, the second file write is based on old information and loses the info from
      # the prior write. Using a global mutex per file path prevents this case.
      #
      # This situation can also occur with multi processing, so file locking is also used for solitary access.
      # File locking is only advisory in some systems, though, so it may only work against other applications
      # that request a lock.
      #
      # @author Robin Miller
      class FileTransaction
         # Holds the mutual exclusion locks for file paths by name
         @file_mutex = {}

         class << self
            attr_reader :file_mutex
         end

         def initialize(path)
            @path = ensure_path(path)
         end

         # Alias for transact(writable: false)
         def read(&block)
            transact(writable: false, &block)
         end

         # Alias for transact(writable: true)
         def write(&block)
            transact(writable: true, &block)
         end

         # Completes the given block as an atomic transaction locked using a global mutex table.
         # The block is provided the current file contents.
         # The block's result is written to the file.
         def transact(writable: false)
            semaphore = FileTransaction.file_mutex[@path.to_s] ||= Mutex.new

            semaphore.synchronize do
               @path.open(writable ? 'r+' : 'r') do |file|
                  file.flock(File::LOCK_EX)

                  yield_result = yield(file.read)
                  if writable
                     file.rewind
                     file.write yield_result
                     file.truncate(file.pos)
                  end
                  yield_result
               end
            end
         end

         private

         def ensure_path(path)
            path = Pathname.new path
            unless path.exist?
               path.dirname.mkpath
               FileUtils.touch path
            end
            path
         end
      end
   end
end
