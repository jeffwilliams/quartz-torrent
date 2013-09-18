require "quartz_torrent/log"
require "quartz_torrent/metainfo"
require "quartz_torrent/udptrackermsg"
require "quartz_torrent/httptrackerclient"
require "quartz_torrent/udptrackerclient"
require "quartz_torrent/interruptiblesleep"
require "quartz_torrent/util"
require "net/http"
require "cgi"
require "thread"
# http://xbtt.sourceforge.net/udp_tracker_protocol.html
# https://wiki.theory.org/BitTorrentSpecification
# http://stackoverflow.com/questions/9669152/get-https-response

module QuartzTorrent
 
  # Represents a peer returned by the tracker
  class TrackerPeer
    def initialize(ip, port, id = nil)
      if ip =~ /(\d+).(\d+).(\d+).(\d+)/
        @ip = ip
        @port = port
        @id = id
      
        @hash = $1.to_i << 24 + 
          $2.to_i << 16 + 
          $3.to_i << 8 +
          $4.to_i +
          port << 32

        @displayId = nil
        @displayId = id.gsub(/[\x80-\xff]/,'?') if id
      else
        raise "Invalid IP address #{ip}"
      end
    end

    def hash
      @hash
    end

    def eql?(o)
      o.ip == @ip && o.port == @port
    end

    # Ip address, a string in dotted-quad notation
    attr_accessor :ip
    attr_accessor :port
    attr_accessor :id

    def to_s
      "#{@displayId ? "["+@displayId+"] " : ""}#{ip}:#{port}"
    end
  end

  # Dynamic parameters needed when making a request to the tracker.
  class TrackerDynamicRequestParams
    def initialize(dataLength = nil)
      @uploaded = 0
      @downloaded = 0
      if dataLength
        @left = dataLength.to_i
      else
        @left = 0
      end
    end
    attr_accessor :uploaded
    attr_accessor :downloaded
    attr_accessor :left
  end

  # Represents the response from a tracker request
  class TrackerResponse
    def initialize(success, error, peers)
      @success = success
      @error = error
      @peers = peers
      @interval = nil
    end

    # The error message if this was not successful
    attr_reader :error

    # The list of peers from the response if the request was a success.
    attr_reader :peers

    # Refresh interval in seconds
    attr_accessor :interval

    # Returns true if the Tracker response was a success
    def successful?
      @success
    end
  end

  # This class represents a connection to a tracker for a specific torrent. It can be used to get
  # peers for that torrent.
  class TrackerClient
    include QuartzTorrent

    def initialize(announceUrl, infoHash, dataLength = 0, maxErrors = 20)
      @peerId = "-QR0001-" # Azureus style
      @peerId << Process.pid.to_s
      @peerId = @peerId + "x" * (20-@peerId.length)
      @stopped = false
      @started = false
      @peers = {}
      @port = 6881
      @peersMutex = Mutex.new
      @errors = []
      @maxErrors = @errors
      @sleeper = InterruptibleSleep.new
      # Event to send on the next update
      @event = :started
      @worker = nil
      @logger = LogManager.getLogger("tracker_client")
      @announceUrl = announceUrl
      @infoHash = infoHash
      @peersChangedListeners = []
      @dynamicRequestParamsBuilder = Proc.new{ TrackerDynamicRequestParams.new(dataLength) }
    end
    
    attr_reader :peerId
    attr_accessor :port
    # This should be set to a Proc that when called will return a TrackerDynamicRequestParams object
    # with up-to-date information.
    attr_accessor :dynamicRequestParamsBuilder

    def started?
      @started
    end

    def peers
      result = nil
      @peersMutex.synchronize do
        result = @peers.keys
      end
      result
    end

    # Add a listener that gets notified when the peers list has changed.
    # This listener is called from another thread so be sure to synchronize
    # if necessary. The passed listener should be a proc that takes no arguments.
    def addPeersChangedListener(listener)
      @peersChangedListeners.push listener
    end
    def removePeersChangedListener(listener)
      @peersChangedListeners.delete listener
    end

    # Get the last N errors reported 
    def errors
      @errors
    end

    # Create a new TrackerClient using the passed information.
    def self.create(announceUrl, infoHash, dataLength = 0, start = true)
      result = nil
      if announceUrl =~ /udp:\/\//
        result = UdpTrackerClient.new(announceUrl, infoHash, dataLength)
      else
        result = HttpTrackerClient.new(announceUrl, infoHash, dataLength)
      end
      result.start if start

      result
    end

    def self.createFromMetainfo(metainfo, start = true)
      create(metainfo.announce, metainfo.infoHash, metainfo.info.dataLength, start)
    end

    # Start the worker thread
    def start
      @stopped = false
      return if @started
      @started = true
      @worker = Thread.new do
        initThread("trackerclient")
        @logger.info "Worker thread starting"
        @event = :started
        trackerInterval = nil
        while ! @stopped
          begin
            response = nil
            begin 
              @logger.debug "Sending request"
              response = request(@event)
              @event = nil
              trackerInterval = response.interval
            rescue
              addError $!
              @logger.debug "Request failed due to exception: #{$!}"
              @logger.debug $!.backtrace.join("\n")
            end

            if response && response.successful?
              # Replace the list of peers
              peersHash = {}
              @logger.info "Response contained #{response.peers.length} peers"
              response.peers.each do |p|
                peersHash[p] = 1
              end
              @peersMutex.synchronize do
                @peers = peersHash
              end
              if @peersChangedListeners.size > 0
                @peersChangedListeners.each{ |l| l.call }
              end
            else
              @logger.debug "Response was unsuccessful from tracker"
              addError response.error if response
            end

            # If we have no interval from the tracker yet, and the last request didn't error out leaving us with no peers,
            # then set the interval to 20 seconds.
            interval = trackerInterval
            interval = 20 if ! interval
            interval = 2 if response && !response.successful? && @peers.length == 0

            @logger.debug "Sleeping for #{interval} seconds"
            @sleeper.sleep interval 

          rescue
            @logger.warn "Unhandled exception in worker thread: #{$!}"
            @logger.warn $!.backtrace.join("\n")
          end
        end
        @logger.info "Worker thread shutting down"
        @logger.info "Sending final update to tracker"
        begin
          request(:stopped)
        rescue
          addError $!
          @logger.debug "Request failed due to exception: #{$!}"
          @logger.debug $!.backtrace.join("\n")
        end
        @started = false
      end
    end

    # Stop the worker thread
    def stop
      @stopped = true
      @sleeper.wake
      if @worker
        @logger.info "Stop called. Waiting for worker"
        @logger.info "Worker wait timed out after 2 seconds. Shutting down anyway" if ! @worker.join(2)
      end
    end

    # Notify the tracker that we have finished downloading all pieces.
    def completed
      @event = :completed
      @sleeper.wake
    end

    # Add an error to the error list
    def addError(e)
      @errors.pop if @errors.length == @maxErrors
      @errors.push e
    end
  
    private
    def eventValid?(event)
      event == :started || event == :stopped || event == :completed
    end
  end


end
