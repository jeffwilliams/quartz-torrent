require "quartz_torrent/log"
require "quartz_torrent/metainfo"
require "quartz_torrent/udptrackermsg"
require "quartz_torrent/httptrackerdriver"
require "quartz_torrent/udptrackerdriver"
require "quartz_torrent/interruptiblesleep"
require "quartz_torrent/util"
require "net/http"
require "cgi"
require "thread"
# http://xbtt.sourceforge.net/udp_tracker_protocol.html
# https://wiki.theory.org/BitTorrentSpecification
# http://stackoverflow.com/questions/9669152/get-https-response

module QuartzTorrent
 
  def filter_non_ascii(s)
    r = ""
    s.each do |c|
      if c >= 32 && c < 128
        r << c.chr
      else
        r << "?"
      end
    end
    r
  end

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
        @displayId = filter_non_ascii(id) if id
      else
        raise "Invalid IP address #{ip}"
      end
    end

    # Hash code of this TrackerPeer.
    def hash
      @hash
    end

    # Equate to another TrackerPeer.
    def eql?(o)
      o.ip == @ip && o.port == @port
    end

    # IP address, a string in dotted-quad notation
    attr_accessor :ip
    # TCP port
    attr_accessor :port
    # Peer Id. This may be nil.
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
      @port = 6881
      @peerId = "-QR0001-" # Azureus style
      @peerId << Process.pid.to_s
      @peerId = @peerId + "x" * (20-@peerId.length)
    end
    # Number of bytes uploaded
    attr_accessor :uploaded
    # Number of bytes downloaded
    attr_accessor :downloaded
    # Number of bytes left to download before torrent is completed
    attr_accessor :left
    attr_accessor :port
    attr_accessor :peerId
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

  # Low-level interface to trackers. TrackerClient uses an instance of a subclass of this to talk to 
  # trackers using different protocols.
  class TrackerDriver
    def initialize(dataLength = 0)
      @dynamicRequestParamsBuilder = Proc.new{ TrackerDynamicRequestParams.new(dataLength) }
    end

    # This should be set to a Proc that when called will return a TrackerDynamicRequestParams object
    # with up-to-date information.
    attr_accessor :dynamicRequestParamsBuilder
    attr_accessor :port
    attr_accessor :peerId

    def request(event = nil)
      raise "Implement me"
    end
  end

  # This class represents a connection to a tracker for a specific torrent. It can be used to get
  # peers for that torrent.
  class TrackerClient
    include QuartzTorrent

    # Create a new TrackerClient
    # @param announceUrl The announce URL of the tracker
    # @param infoHash    The infoHash of the torrent we're tracking
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
      @announceUrlList = announceUrl
      @infoHash = infoHash
      @peersChangedListeners = []
      @dynamicRequestParamsBuilder = Proc.new do 
        result = TrackerDynamicRequestParams.new(dataLength) 
        result.port = @port
        result.peerId = @peerId
        result
      end
      @alarms = nil

      # Convert announceUrl to an array
      if @announceUrlList.nil?
        @announceUrlList = []
      elsif @announceUrlList.is_a? String
        @announceUrlList = [@announceUrlList]
        @announceUrlList.compact!
      else
        @announceUrlList = @announceUrlList.flatten.sort.uniq
      end

      raise "AnnounceURL contained no valid trackers" if @announceUrlList.size == 0
  
      @announceUrlIndex = 0
    end
    
    attr_reader :peerId
    attr_accessor :port
    # This should be set to a Proc that when called will return a TrackerDynamicRequestParams object
    # with up-to-date information.
    attr_accessor :dynamicRequestParamsBuilder

    # This member can be set to an Alarms object. If it is, this tracker will raise alarms
    # when it doesn't get a response, and clear them when it does.
    attr_accessor :alarms

    # Return true if this TrackerClient is started, false otherwise.
    def started?
      @started
    end

    # Return the list of peers that the TrackerClient knows about. This list grows over time
    # as more peers are reported from the tracker.
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

    # Create a new TrackerClient using the passed information. The announceUrl may be a string or a list.
    def self.create(announceUrl, infoHash, dataLength = 0, start = true)
      result = TrackerClient.new(announceUrl, infoHash, dataLength)
      result.start if start
      result
    end

    # Create a new TrackerClient using the passed Metainfo object.
    def self.createFromMetainfo(metainfo, start = true)
      announce = []
      announce.push metainfo.announce if metainfo.announce
      announce = announce.concat(metainfo.announceList) if metainfo.announceList
      create(announce, metainfo.infoHash, metainfo.info.dataLength, start)
    end

    # Create a TrackerDriver for the specified URL. TrackerDriver is a lower-level interface to the tracker.
    def self.createDriver(announceUrl, infoHash)
      result = nil
      if announceUrl =~ /udp:\/\//
        result = UdpTrackerDriver.new(announceUrl, infoHash)
      else
        result = HttpTrackerDriver.new(announceUrl, infoHash)
      end
      result
    end

    # Create a TrackerDriver using the passed Metainfo object. TrackerDriver is a lower-level interface to the tracker.
    def self.createDriverFromMetainfo(metainfo)
      TrackerClient.createDriver(metainfo.announce, metainfo.infoHash)
    end

    # Start the worker thread
    def start
      @stopped = false
      return if @started
      @started = true
      @worker = Thread.new do
        QuartzTorrent.initThread("trackerclient")
        @logger.info "Worker thread starting"
        @event = :started
        trackerInterval = nil
        while ! @stopped
          begin
            response = nil

            driver = currentDriver

            if driver
              begin 
                @logger.debug "Sending request to tracker #{currentAnnounceUrl}"
                response = driver.request(@event)
                @event = nil
                trackerInterval = response.interval
              rescue
                addError $!
                @logger.info "Request failed due to exception: #{$!}"
                @logger.debug $!.backtrace.join("\n")
                changeToNextTracker
                next

                @alarms.raise Alarm.new(:tracker, "Tracker request failed: #{$!}") if @alarms
              end
            end

            if response && response.successful?
              @alarms.clear :tracker if @alarms
              # Replace the list of peers
              peersHash = {}
              @logger.info "Response contained #{response.peers.length} peers"

              if response.peers.length == 0
                @alarms.raise Alarm.new(:tracker, "Response from tracker contained no peers") if @alarms
              end

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
              @logger.info "Response was unsuccessful from tracker: #{response.error}"
              addError response.error if response
              @alarms.raise Alarm.new(:tracker, "Unsuccessful response from tracker: #{response.error}") if @alarms && response
              changeToNextTracker
              next
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
            @sleeper.sleep 1
          end
        end
        @logger.info "Worker thread shutting down"
        @logger.info "Sending final update to tracker"
        begin
          driver = currentDriver
          driver.request(:stopped) if driver
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

    def currentDriver
      announceUrl = currentAnnounceUrl
      return nil if ! announceUrl
           
      driver = TrackerClient.createDriver announceUrl, @infoHash
      driver.dynamicRequestParamsBuilder = @dynamicRequestParamsBuilder if driver
      driver.port = @port
      driver.peerId = @peerId
      driver
    end

    def currentAnnounceUrl
      return nil if @announceUrlList.size == 0
      @announceUrlIndex = 0 if @announceUrlIndex > @announceUrlList.size-1

      @announceUrlList[@announceUrlIndex]
    end

    def changeToNextTracker
      @announceUrlIndex += 1
      @logger.info "Changed to next tracker #{currentAnnounceUrl}"
      sleep 0.5
    end

  end


end
