require "./src/log"
require "./src/metainfo"
require "./src/udptrackermsg"
require "./src/httptrackerclient"
require "./src/udptrackerclient"
require "./src/interruptiblesleep"
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
      "#{id ? "["+id+"] " : ""}#{ip}:#{port}"
    end
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
    def initialize(maxErrors = 20)
      @peerId = "-QR0001-" # Azureus style
      @peerId << Process.pid.to_s
      @peerId = @peerId + "x" * (20-@peerId.length)
      @stopped = false
      @started = false
      @peers = {}
      @peersMutex = Mutex.new
      @errors = []
      @maxErrors = @errors
      @sleeper = InterruptibleSleep.new
      # Event to send on the next update
      @event = :started
      @worker = nil
      @logger = LogManager.getLogger("tracker_client")
      @metainfo = nil
      @peersChangedListeners = []
    end
    
    attr_reader :peerId
    attr_reader :metainfo

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

    def self.create(metainfo)
      result = nil
      if metainfo.announce =~ /udp:\/\//
        result = UdpTrackerClient.new(metainfo)
      else
        result = HttpTrackerClient.new(metainfo)
      end
      result.start

      result
    end

    # Start the worker thread
    def start
      @stopped = false
      return if @started
      @started = true
      @worker = Thread.new do
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

if $0 =~ /src\/trackerclient.rb/
  torrent = ARGV[0]
  if ! torrent
    torrent = "tests/data/testtorrent.torrent"
  end
  metainfo = QuartzTorrent::Metainfo.createFromFile(torrent)
  client = QuartzTorrent::TrackerClient.create(metainfo)
  
  running = true

  Signal.trap('SIGINT') do
    puts "Got SIGINT"
    running = false
  end

  while running do
    result = client.peers
    puts result.inspect
    puts "PEERS:"
    puts "  " + result.join("\n  ")
    sleep 2
  end
 
  client.stop
  
end
