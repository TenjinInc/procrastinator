# frozen_string_literal: true

module Procrastinator
   # Mixin module that adds log file support
   module Loggable
      # Starts a log file and stores the logger within this queue worker.
      #
      # Separate from init because logging is context-dependent
      def open_log!(name, config)
         return unless config.log_level

         log_path = config.log_dir / "#{ name }.log"

         config.log_dir.mkpath
         FileUtils.touch(log_path)

         Logger.new(log_path.to_path,
                    config.log_shift_age, config.log_shift_size,
                    level:    config.log_level,
                    progname: name)
      end
   end
end
