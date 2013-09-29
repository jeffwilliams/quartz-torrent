require 'logger'

module QuartzTorrent
  # Class used to control logging.
  class LogManager

    # A fake IO object whose write and close methods do nothing.
    class NullIO
      def write(msg)
      end
      def close
      end
    end

    @@logFile = NullIO.new 
    @@loggers = {}
    @@levels = {}
    @@defaultLevel = Logger::ERROR
    @@maxOldLogs = 10
    @@maxLogSize = 1048576

    # Initialize logging information from the environment. The environment variable
    # QUARTZ_TORRENT_LOGFILE specifies which file logging is written to, and can also take the 
    # values 'stdout' or 'stderr'. The environment variable QUARTZ_TORRENT_LOGLEVEL specifies the
    # default logging level for all loggers.
    def self.initializeFromEnv
      dest = ENV['QUARTZ_TORRENT_LOGFILE']
      level = ENV['QUARTZ_TORRENT_LOGLEVEL']
  
      self.logFile = dest
      self.defaultLevel = level

    end

    # Set the logfile.
    # This method doesn't change the log file if loggers have already
    # been created by getLogger
    def self.logFile=(dest)
      if dest
        if dest.downcase == 'stdout'
          dest = STDOUT
        elsif dest.downcase == 'stderr' 
          dest = STDERR
        end
      else
        dest = NullIO.new
      end
      @@logFile = dest
    end

    # Set log level for the named logger. The level can be one of
    # fatal, error, warn, info, or debug as a string or symbol.
    def self.setLevel(name, level)
      level = parseLogLevel(level)
      @@levels[name] = level
      logger = @@loggers[name]
      if logger
        logger.level = level
      end
    end

    # Set default log level. The level can be one of
    # fatal, error, warn, info, or debug as a string or symbol.
    def self.defaultLevel=(level)
      @@defaultLevel = parseLogLevel(level)
    end

    # Set number of old log files to keep when rotating.
    def self.maxOldLogs=(num)
      @@maxOldLogs = num
    end

    # Max size of a single logfile in bytes
    def self.maxLogSize=(size)
      @@maxLogSize = size
    end

    def self.getLogger(name)
      logger = @@loggers[name] 
      if ! logger
        logger = Logger.new(@@logFile, @@maxOldLogs, @@maxLogSize)
        level = @@levels[name]
        if level
          logger.level = level
        else
          logger.level = @@defaultLevel
        end
        logger.progname = name
        
        @@loggers[name] = logger
      end
      logger
    end

    private
    def self.parseLogLevel(level)
      if level
        if level.is_a? Symbol
          if level == :fatal
            level = Logger::FATAL
          elsif level == :error
            level = Logger::ERROR
          elsif level == :warn
            level = Logger::WARN
          elsif level == :info
            level = Logger::INFO
          elsif level == :debug
            level = Logger::DEBUG
          else
            level = Logger::ERROR
          end
        else
          if level.downcase == 'fatal'
            level = Logger::FATAL
          elsif level.downcase == 'error'
            level = Logger::ERROR
          elsif level.downcase == 'warn'
            level = Logger::WARN
          elsif level.downcase == 'info'
            level = Logger::INFO
          elsif level.downcase == 'debug'
            level = Logger::DEBUG
          else
            level = Logger::ERROR
          end
        end
      else
        level = Logger::ERROR
      end
      level
    end
  end
end
