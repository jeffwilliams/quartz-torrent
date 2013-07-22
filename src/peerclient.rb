$: << "."
require "src/log.rb"
require "src/trackerclient.rb"
require "src/peermsg.rb"
require "src/reactor.rb"
require "src/util.rb"
require "src/classifiedpeers.rb"
require "src/classifiedpeers.rb"
require "src/peerholder.rb"
require "src/peermanager.rb"
require "src/blockstate.rb"
require "src/filemanager.rb"

include QuartzTorrent

module QuartzTorrent
 
  class PieceManagerRequestMetadata
    def initialize(type, data)
      @type = type
      @data = data
    end
    attr_accessor :type
    attr_accessor :data
  end
 
  class TorrentData
    def initialize(metainfo, trackerClient)
      @metainfo = metainfo
      @trackerClient = trackerClient
      @peerManager = PeerManager.new
      @pieceManagerRequestMetadata = {}
    end
    attr_accessor :metainfo
    attr_accessor :trackerClient
    attr_accessor :peerManager
    attr_accessor :blockState
    attr_accessor :pieceManager
    attr_accessor :pieceManagerRequestMetadata
    attr_accessor :peerChangeListener
  end

  # Implements a Reactor handler
  class PeerClientHandler < QuartzTorrent::Handler
    def initialize(baseDirectory)
      # Hash of TorrentData objects, keyed by torrent infoHash
      @torrentData = {}

      @baseDirectory = baseDirectory

      # Peers
      @peers = PeerHolder.new
      @logger = LogManager.getLogger("peerclient")

      # Number of peers we ideally want to try and be downloading/uploading with
      @targetActivePeerCount = 50
      @targetUnchokedPeerCount = 4
      @managePeersPeriod = 10 # Defined in bittorrent spec. Only unchoke peers every 10 seconds.
      @requestBlocksPeriod = 1
    end

    attr_reader :torrentData

    # Add a new tracker client. This effectively adds a new torrent to download.
    def addTrackerClient(trackerclient)
      raise "There is already a tracker registered for torrent #{bytesToHex(trackerclient.metainfo.infoHash)}" if @torrentData.has_key? trackerclient.metainfo.infoHash
      torrentData = TorrentData.new(trackerclient.metainfo, trackerclient)

      # Check the existing pieces of the torrent.
      @logger.error "Checking pieces of torrent #{bytesToHex(trackerclient.metainfo.infoHash)} synchronously. RECODE THIS"
      torrentData.pieceManager = QuartzTorrent::PieceManager.new(@baseDirectory, trackerclient.metainfo)
      torrentData.pieceManager.findExistingPieces
      torrentData.pieceManager.wait
      existingBitfield = torrentData.pieceManager.nextResult.data
      @logger.info "We already have #{existingBitfield.countSet}/#{existingBitfield.length} pieces." 
     
      torrentData.blockState = BlockState.new(trackerclient.metainfo, existingBitfield)

      @torrentData[trackerclient.metainfo.infoHash] = torrentData
    
      metaInfo = trackerclient.metainfo
      @logger.info "Added torrent #{bytesToHex(trackerclient.metainfo.infoHash)}. Information:"
      @logger.info "  piece length:     #{metaInfo.info.pieceLen}"
      @logger.info "  number of pieces: #{metaInfo.info.pieces.size}"
      @logger.info "  total length      #{metaInfo.info.dataLength}"

      # Add a listener for when the tracker's peers change.
      torrentData.peerChangeListener = Proc.new do 
        @logger.info "Managing peers for torrent #{bytesToHex(trackerclient.metainfo.infoHash)} on peer change event"
        managePeers(trackerclient.metainfo.infoHash) 
      end
      trackerclient.addPeersChangedListener torrentData.peerChangeListener

      # Schedule peer connection management. Recurring and immediate 
      @reactor.scheduleTimer(@managePeersPeriod, [:manage_peers, trackerclient.metainfo.infoHash], true, true)
      # Schedule requesting blocks from peers. Recurring and immediate
      @reactor.scheduleTimer(@requestBlocksPeriod, [:request_blocks, trackerclient.metainfo.infoHash], true, true)
      # Schedule checking for PieceManager results
      @reactor.scheduleTimer(@requestBlocksPeriod, [:check_piece_manager, trackerclient.metainfo.infoHash], true, true)
    end

    # Remove a torrent.
    def removeTorrent(infoHash)
      torrentData = @torrentData.delete infoHash
  
      if torrentData    
        torrentData.trackerClient.removePeersChangedListener(torrentData.peerChangeListener)
      end

      # Delete all peers related to this torrent
      # Can't do this right now, since it could be in use by an event handler. Use an immediate, non-recurring timer instead.
      reactor.scheduleTimer(0, [:removetorrent, infoHash], false, true)
    end

    def serverInit(metadata, addr, port)
      # A peer connected to us
      # Read handshake message
      begin
        msg = PeerHandshake.unserializeFrom currentIo
      rescue
        @logger.warn "Peer #{peer.trackerPeer.to_s} failed handshake: #{$!}"
        peer.state = :disconnected
        close
        return
      end
      
      peer = @peers.findById(msg.peerId)
      if peer
        if peer.ip != addr || peer.port != port
          @logger.warn "Peer with id #{msg.peerId} connected from #{addr}:#{port}, but a peer with that id already exists at #{peer.ip}:#{peer.port}. Closing connection from new peer."
          peer.state = :disconnected
          close
          return
        end

        if peer.state != :disconnected
          @logger.warn "Peer with id #{msg.peerId} created a new connection when we already have a connection in state #{peer.state}. Closing new connection."
          peer.state = :disconnected
          close
          return
        end
      else
        peer = Peer.new(TrackerPeer.new(addr, port))
        peer.trackerPeer.id = msg.peerId
        peer.state = :handshaking
        @peers.add peer
      end

      @logger.info "Peer #{peer.trackerPeer} connected to us. "

      processHandshake(msg, peer)

      # Send handshake
      msg = PeerHandshake.new
      msg.peerId = trackerclient.peerId
      msg.infoHash = peer.infoHash
      msg.serializeTo currentIo
      peer.state = :established

      setMetaInfo(peer)
    end

    def clientInit(peer)
      # We connected to a peer
      # Send handshake
      torrentData = @torrentData[peer.infoHash]
      if ! torrentData
        @logger.warn "No tracker client found for peer #{peer.trackerPeer.to_s}. Closing connection."
        close
        return
      end
      trackerclient = torrentData.trackerClient

      @logger.info "Connected to peer #{peer.trackerPeer}. Sending handshake."
      msg = PeerHandshake.new
      msg.peerId = trackerclient.peerId
      msg.infoHash = peer.infoHash
      msg.serializeTo currentIo
      peer.state = :handshaking
      @logger.info "Done sending handshake."
    end

    def recvData(peer)
      msg = nil

      @logger.debug "Got data from peer #{peer.trackerPeer}"

      if peer.state == :handshaking
        # Read handshake message
        begin
          @logger.debug "Reading handshake from #{peer.trackerPeer}"
          msg = PeerHandshake.unserializeFrom currentIo
        rescue
          @logger.warn "Peer #{peer.trackerPeer.to_s} failed handshake: #{$!}"
          peer.state = :disconnected
          close
          return
        end
      else
        begin
          @logger.debug "Reading wire-message from #{peer.trackerPeer}"
          msg = PeerWireMessage.unserializeFrom currentIo
        rescue EOFError
          @logger.info "Peer #{peer.trackerPeer.to_s} disconnected."
          peer.state = :disconnected
          close
          return
        rescue
          @logger.warn "Unserializing message from peer #{peer.trackerPeer.to_s} failed: #{$!}"
          @logger.warn $!.backtrace.join "\n"
          peer.state = :disconnected
          close
          return
        end
        peer.updateUploadRate msg
        @logger.info "Peer #{peer.trackerPeer.to_s} upload rate: #{peer.uploadRate.value}  data only: #{peer.uploadRateDataOnly.value}"
      end


      if msg.is_a? PeerHandshake
        # This is a remote peer that we connected to returning our handshake.
        processHandshake(msg, peer)
        peer.state = :established
      elsif msg.is_a? BitfieldMessage
        @logger.warn "Received bitfield message from peer."
        peer.bitfield = msg.bitfield
      elsif msg.is_a? Unchoke
        @logger.warn "Received unchoke message from peer."
        peer.amChoked = false
      elsif msg.is_a? Choke
        @logger.warn "Received choke message from peer."
        peer.amChoked = true
      elsif msg.is_a? Interested
        @logger.warn "Received interested message from peer."
        peer.peerInterested = true
      elsif msg.is_a? Uninterested
        @logger.warn "Received uninterested message from peer."
        peer.peerInterested = false
      elsif msg.is_a? Piece
        @logger.warn "Received piece message from peer for torrent #{bytesToHex(peer.infoHash)}: piece #{msg.pieceIndex} offset #{msg.blockOffset} length #{msg.data.length}."
        handlePieceReceive(msg, peer)
      elsif msg.is_a? KeepAlive
        @logger.warn "Received keep alive message from peer."
      else
        @logger.warn "Received a #{msg.class} message but handler is not implemented"
      end
    end

    def timerExpired(metadata)
      if metadata.is_a?(Array) && metadata[0] == :manage_peers
        @logger.info "Managing peers for torrent #{bytesToHex(metadata[1])}"
        managePeers(metadata[1])
      elsif metadata.is_a?(Array) && metadata[0] == :request_blocks
        #@logger.info "Requesting blocks for torrent #{bytesToHex(metadata[1])}"
        requestBlocks(metadata[1])
      elsif metadata.is_a?(Array) && metadata[0] == :check_piece_manager
        #@logger.info "Checking for PieceManager results"
        checkPieceManagerResults(metadata[1])
      elsif metadata.is_a?(Array) && metadata[0] == :removetorrent
        # Remove all the peers for this torrent.
        list = Array.new(@peers.findByInfoHash(metadata[1]))
        list.each do |peer|
          # Close socket 
          io = findIoByMetainfo(peer)
          if io
            peer.state = :disconnected
            close(io)
          else
            @logger.info "Couldn't find io associated with peer #{peer.trackerPeer}. Maybe it was already deleted."
          end
          @peers.deleteById peer.trackerPeer.id
        end
      else
        @logger.info "Unknown timer #{metadata} expired."
      end
    end

    def error(peer, details)
      @logger.info "Error with peer: #{details}"
    end
    
    private
    def processHandshake(msg, peer)
      if @peers.findById msg.peerId
        @logger.warn "Peer #{peer.trackerPeer.to_s} failed handshake: this peer is already connected."
        close
        return
      end

      torrentData = @torrentData[msg.infoHash]
      # Are we tracking this torrent?
      if !torrentData
        @logger.info "Peer #{peer.trackerPeer.to_s} failed handshake: we are not managing torrent #{bytesToHex(msg.infoHash)}"
        peer.state = :disconnected
        close
        return 
      end
      trackerclient = torrentData.trackerClient

      @logger.info "peer #{peer.trackerPeer.to_s} sent valid handshake for torrent #{bytesToHex(msg.infoHash)}"
      peer.infoHash = msg.infoHash
      # If this was a peer we got from a tracker that had no id then we only learn the id on handshake.
      peer.trackerPeer.id = msg.peerId
      @peers.idSet peer
    end

    def managePeers(infoHash)
      torrentData = @torrentData[infoHash]
      if ! torrentData
        @logger.error "Manage peers: tracker client for torrent #{bytesToHex(infoHash)} not found."
        return
      end
      trackerclient = torrentData.trackerClient

      # Update our internal peer list for this torrent from the tracker client
      trackerclient.peers.each do |p| 
        if ! @peers.findByAddr(p.ip, p.port)
          @logger.debug "Adding tracker peer #{p} to peers list"
          peer = Peer.new(p)
          peer.infoHash = infoHash
          @peers.add peer
        end
      end

      peers = @peers.findByInfoHash(infoHash)
      classifiedPeers = ClassifiedPeers.new peers

      manager = torrentData.peerManager
      if ! manager
        @logger.error "Manage peers: peer manager client for torrent #{bytesToHex(infoHash)} not found."
        return
      end

      toConnect = manager.manageConnections(classifiedPeers)
      toConnect.each do |peer|
        @logger.info "Connecting to peer #{peer.trackerPeer}"
        connect peer.trackerPeer.ip, peer.trackerPeer.port, peer
      end

      manageResult = manager.managePeers(classifiedPeers)
      manageResult.unchoke.each do |peer|
        @logger.info "Unchoking peer #{peer.trackerPeer}"
        io = findIoByMetainfo(peer)
        if io
          msg = Unchoke.new
          msg.serializeTo io
          peer.peerChoked = false
        else
          @logger.info "Unchoking peer #{peer.trackerPeer} failed: Couldn't find peer's io from reactor"
        end
      end

      manageResult.choke.each do |peer|
        @logger.info "Choking peer #{peer.trackerPeer}"
        io = findIoByMetainfo(peer)
        if io
          msg = Choke.new
          msg.serializeTo io
          peer.peerChoked = true
        else
          @logger.info "Choking peer #{peer.trackerPeer} failed: Couldn't find peer's io from reactor"
        end
      end

    end

    def requestBlocks(infoHash)
      torrentData = @torrentData[infoHash]
      if ! torrentData
        @logger.error "Request blocks peers: tracker client for torrent #{bytesToHex(infoHash)} not found."
        return
      end

      #@logger.debug @peers.to_s(infoHash)


      peers = @peers.findByInfoHash(infoHash)
      classifiedPeers = ClassifiedPeers.new peers

      blockInfos = torrentData.blockState.findRequestableBlocks(classifiedPeers, 10)
      blockInfos.each do |blockInfo|
        peer = blockInfo.peers.first
        io = findIoByMetainfo(peer)
        if io
          if ! peer.amInterested
            # Let this peer know that I'm interested if I haven't yet.
            msg = Interested.new
            msg.serializeTo io
            peer.amInterested = true
          end
          @logger.info "Requesting block from #{peer.trackerPeer}: piece #{blockInfo.pieceIndex} offset #{blockInfo.offset} length #{blockInfo.length}"
          msg = blockInfo.getRequest
          msg.serializeTo io
          torrentData.blockState.setBlockRequested blockInfo, true
        else
          @logger.info "Unchoking peer #{peer.trackerPeer} failed: Couldn't find peer's io from reactor"
        end
      end
    end

    # Send interested or uninterested messages to peers.
    def updateInterested
      
    end

    def handlePieceReceive(msg, peer)
      torrentData = @torrentData[peer.infoHash]
      if ! torrentData
        @logger.error "Receive piece: torrent data for torrent #{bytesToHex(peer.infoHash)} not found."
        return
      end
      blockIndexWithinPiece = msg.blockOffset / torrentData.blockState.blockSize
      id = torrentData.pieceManager.writeBlock(msg.pieceIndex, blockIndexWithinPiece, torrentData.blockState.blockSize, msg.data)
      torrentData.pieceManagerRequestMetadata[id] = PieceManagerRequestMetadata.new(:write, msg)
    end

    def checkPieceManagerResults(infoHash)
      torrentData = @torrentData[infoHash]
      if ! torrentData
        @logger.error "Request blocks peers: tracker client for torrent #{bytesToHex(infoHash)} not found."
        return
      end
 
      while true
        result = torrentData.pieceManager.nextResult
        break if ! result
        metaData = torrentData.pieceManagerRequestMetadata[result.requestId]
        if ! metaData
          @logger.error "Can't find metadata for PieceManager request #{result.requestId}"
          return
        end
      
        if metaData.type == :write
          if result.successful?
            @logger.info "Block written to disk. "
            # Block successfully written!
            torrentData.blockState.setBlockCompleted metaData.data.pieceIndex, metaData.data.blockOffset, true do |pieceIndex|
              # The peice is completed! Check hash.
              @logger.info "Piece #{pieceIndex} is complete. Checking hash. "
              id = torrentData.pieceManager.checkPieceHash(metaData.data.pieceIndex)
              torrentData.pieceManagerRequestMetadata[id] = PieceManagerRequestMetadata.new(:hash, metaData.data.pieceIndex)
            end
          else
            # Block failed! Clear completed and requested state.
            torrentData.blockState.setBlockCompleted metaData.data.pieceIndex, metaData.data.blockOffset, false
            @logger.error "Writing block failed: #{result.error}"
          end
        elsif metaData.type == :hash
          if result.successful?
            @logger.info "Hash of piece #{metaData.data} is correct"
          else
            @logger.info "Hash of piece #{metaData.data} is incorrect. Marking piece as not complete."
            torrentData.blockState.setPieceCompleted metaData.data, false
          end
        end
      end

    end
  end

  # Represents a client that talks to bittorrent peers
  # This class implements a Reactor Handler.
  class PeerClient 
    # Use select and non-blocking IO (10K problem: the file descriptor might not be ready anymore when you try to read from it. That's why it's important to use nonblocking mode when using readiness notification. )
    #  - When connecting or disconnecting, add connecting sockets to select set. (select only allows FDs up to 1024!)
    #  - When connected send handshake info and add back into select set.
    #  - When peer connects send handshake and add back into select set.
    #  - When downloading a piece, generate the SHA1 on the fly, and pass blocks to another queue/threadpool for writing to disk since writing to disk is blocky and slow.
    #  - On timeout, evaluate the situation. Unchoke some peers, choke others, etc.
    #  - In general peers are advised to keep a few unfullfilled requests on each connection. This is done because otherwise a full round trip is required 
    #    from the download of one block to begining the download of a new block (round trip between PIECE message and next REQUEST message). On links with high BDP (bandwidth-delay-product, 
    #    high latency or high bandwidth), this can result in a substantial performance loss. Jeff Note: Basically if we're not queueing requests to a peer, then between when we finish reading
    #    a block until the start of the next block the download bandwidth is idle (since we have to send a request and wait)    

    def initialize(baseDirectory)
      @port = 9998
      @handler = nil
      @stopped = true
      @reactor = nil
      @logger = LogManager.getLogger("peerclient")
      @worker = nil
      @handler = PeerClientHandler.new baseDirectory
      @reactor = QuartzTorrent::Reactor.new(@handler, LogManager.getLogger("peerclient.reactor"))
    end

    attr_accessor :port

    def start 
      @reactor.listen("0,0,0,0",@port,:listener_socket)

      @stopped = false
      @worker = Thread.new do
        @reactor.start 
        @logger.info "Reactor stopped."
        @handler.torrentData.each do |k,v|
          v.trackerClient.stop
        end 
      end
    end

    def stop
      @logger.info "Stop called. Stopping reactor"
      @reactor.stop
      if @worker
        @logger.info "Worker wait timed out after 10 seconds. Shutting down anyway" if ! @worker.join(10)
      end
    end

    # Add a new torrent to manage.
    def addTrackerClient(trackerclient)
      trackerclient.start if ! trackerclient.started?
      @handler.addTrackerClient(trackerclient)
    end
  end
end

if $0 =~ /peerclient.rb$/
  require 'fileutils'

  QuartzTorrent::LogManager.initializeFromEnv
  #QuartzTorrent::LogManager.setLevel "peerclient", :info
  LogManager.logFile= "stdout"
  LogManager.defaultLevel= :info
  LogManager.setLevel "peer_manager", :debug
  LogManager.setLevel "tracker_client", :debug
  LogManager.setLevel "http_tracker_client", :debug
  LogManager.setLevel "peerclient", :debug
  LogManager.setLevel "peerclient.reactor", :info
  LogManager.setLevel "blockstate", :debug
  LogManager.setLevel "piecemanager", :info
  
  BASE_DIRECTORY = "tmp"
  FileUtils.mkdir BASE_DIRECTORY if ! File.exists?(BASE_DIRECTORY)

  torrent = ARGV[0]
  if ! torrent
    torrent = "tests/data/testtorrent.torrent"
  end
  puts "Loading torrent #{torrent}"
  metainfo = QuartzTorrent::Metainfo.createFromFile(torrent)
  trackerclient = QuartzTorrent::TrackerClient.create(metainfo)
  peerclient = QuartzTorrent::PeerClient.new(BASE_DIRECTORY)
  peerclient.addTrackerClient(trackerclient)


  running = true

  puts "Creating signal handler"
  Signal.trap('SIGINT') do
    puts "Got SIGINT. Shutting down."
    running = false
  end

  puts "Starting peer client"
  peerclient.start

  while running do
    sleep 2
    
  end
 
  peerclient.stop
  
end
