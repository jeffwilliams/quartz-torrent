require 'log4r'

# For some reason the Log4r log level constants (ERROR, etc) are not defined until we 
# create at least one logger. Here I create one unused one so that the constants exist.
Log4r::Logger.new '__init'

module QuartzTorrent
  # Class used to control logging.
  class LogManager

    @@outputter = nil
    @@formatter = Log4r::PatternFormatter.new(:pattern => "%d %l %m")
    @@defaultLevel = Log4r::ERROR
    @@maxOldLogs = 10
    @@maxLogSize = 1048576
    @@dest = nil

    # Initialize logging based on environment variables. The QUARTZ_TORRENT_LOGFILE variable controls where logging is written,
    # and should be either a file path, 'stdout' or 'stderr'.
    def self.initializeFromEnv
      @@dest = ENV['QUARTZ_TORRENT_LOGFILE']
      @@defaultLevel = parseLogLevel(ENV['QUARTZ_TORRENT_LOGLEVEL'])
  
    end

    # Initialize the log manager. This method expects a block, and the block may call the following methods:
    #
    #   setLogfile(path)
    #   setDefaultLevel(level)
    #   setMaxOldLogs(num)
    #   setMaxLogSize(size)
    #
    # In the above methods, `path` defines where logging is written, and should be either a file path, 'stdout' or 'stderr';
    # `level` is a logging level as per setLevel, `num` is an integer, and `size` is a value in bytes.
    def self.setup(&block)
      self.instance_eval &block

      dest = @@dest
      if dest
        if dest.downcase == 'stdout'
          dest = Log4r::Outputter.stdout
        elsif dest.downcase == 'stderr' 
          dest = Log4r::Outputter.stderr
        else
          dest = Log4r::RollingFileOutputter.new('outputter', {filename: dest, maxsize: @@maxLogSize, max_backups: @@maxOldLogs})
        end
      end
      @@outputter = dest
      @@outputter.formatter = @@formatter
    end

    # Set log level for the named logger. The level can be one of
    # fatal, error, warn, info, or debug as a string or symbol.
    def self.setLevel(name, level)
      level = parseLogLevel(level)
      logger = LogManager.getLogger(name)
      logger.level = level
    end

    # Get the logger with the specified name. Currently this returns a log4r Logger.
    def self.getLogger(name)
      if ! @@outputter
        Log4r::Logger.root
      else
        logger = Log4r::Logger[name]
        if ! logger
          logger = Log4r::Logger.new name
          logger.level = @@defaultLevel
          logger.outputters = @@outputter
        end
        logger
      end
    end

    private
    # DSL method used by setup.
    # Set the logfile.
    def self.setLogfile(dest)
      @@dest = dest
    end
    # DSL method used by setup.
    # Set the default log level.
    def self.setDefaultLevel(level)
      @@defaultLevel = parseLogLevel(level)
    end

    # Set number of old log files to keep when rotating.
    def self.setMaxOldLogs(num)
      @@maxOldLogs = num
    end

    # Max size of a single logfile in bytes
    def self.setMaxLogSize(size)
      @@maxLogSize = size
    end

    def self.parseLogLevel(level)
      if level
        if level.is_a? Symbol
          if level == :fatal
            level = Log4r::FATAL
          elsif level == :error
            level = Log4r::ERROR
          elsif level == :warn
            level = Log4r::WARN
          elsif level == :info
            level = Log4r::INFO
          elsif level == :debug
            level = Log4r::DEBUG
          else
            level = Log4r::ERROR
          end
        else
          if level.downcase == 'fatal'
            level = Log4r::FATAL
          elsif level.downcase == 'error'
            level = Log4r::ERROR
          elsif level.downcase == 'warn'
            level = Log4r::WARN
          elsif level.downcase == 'info'
            level = Log4r::INFO
          elsif level.downcase == 'debug'
            level = Log4r::DEBUG
          else
            level = Log4r::ERROR
          end
        end
      else
        level = Log4r::ERROR
      end
      level
    end
  end
end
