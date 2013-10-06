require 'log4r'
include Log4r

# For some reason the Log4r log level constants (ERROR, etc) are not defined until we 
# create at least one logger. Here I create one unused one so that the constants exist.
Logger.new '__init'

module QuartzTorrent
  # Class used to control logging.
  class LogManager

    @@outputter = nil
    @@defaultLevel = Log4r::ERROR
    @@maxOldLogs = 10
    @@maxLogSize = 1048576
    @@dest = nil

    def self.initializeFromEnv
      @@dest = ENV['QUARTZ_TORRENT_LOGFILE']
      @@defaultLevel = parseLogLevel(ENV['QUARTZ_TORRENT_LOGLEVEL'])
  
    end

    # Initialize the log manager using some defaults.
    def self.setup(&block)
      self.instance_eval &block

      dest = @@dest
      if dest
        if dest.downcase == 'stdout'
          dest = Outputter.stdout
        elsif dest.downcase == 'stderr' 
          dest = Outputter.stderr
        else
          dest = RollingFileOutputter.new('outputter', {filename: dest, maxsize: @@maxLogSize, max_backups: @@maxOldLogs})
        end
      end
      @@outputter = dest
    end

    # Set log level for the named logger. The level can be one of
    # fatal, error, warn, info, or debug as a string or symbol.
    def self.setLevel(name, level)
      level = parseLogLevel(level)
      logger = LogManager.getLogger(name)
      logger.level = level
    end

    def self.getLogger(name)
      if ! @@outputter
        Logger.root
      else
        logger = Logger[name]
        if ! logger
          logger = Logger.new name
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
            level = FATAL
          elsif level == :error
            level = ERROR
          elsif level == :warn
            level = WARN
          elsif level == :info
            level = INFO
          elsif level == :debug
            level = DEBUG
          else
            level = ERROR
          end
        else
          if level.downcase == 'fatal'
            level = FATAL
          elsif level.downcase == 'error'
            level = ERROR
          elsif level.downcase == 'warn'
            level = WARN
          elsif level.downcase == 'info'
            level = INFO
          elsif level.downcase == 'debug'
            level = DEBUG
          else
            level = ERROR
          end
        end
      else
        level = ERROR
      end
      level
    end
  end
end
