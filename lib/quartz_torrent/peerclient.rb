require "quartz_torrent/log.rb"
require "quartz_torrent/trackerclient.rb"
require "quartz_torrent/peermsg.rb"
require "quartz_torrent/reactor.rb"
require "quartz_torrent/util.rb"
require "quartz_torrent/classifiedpeers.rb"
require "quartz_torrent/classifiedpeers.rb"
require "quartz_torrent/peerholder.rb"
require "quartz_torrent/peermanager.rb"
require "quartz_torrent/blockstate.rb"
require "quartz_torrent/filemanager.rb"
require "quartz_torrent/semaphore.rb"


module QuartzTorrent
 
  # Metadata associated with outstanding requests to the PieceManager (asynchronous IO management).
  class PieceManagerRequestMetadata
    def initialize(type, data)
      @type = type
      @data = data
    end
    attr_accessor :type
    attr_accessor :data
  end
 
  # Extra metadata stored in a PieceManagerRequestMetadata specific to read requests.
  class ReadRequestMetadata
    def initialize(peer, requestMsg)
      @peer = peer
      @requestMsg = requestMsg
    end
    attr_accessor :peer
    attr_accessor :requestMsg
  end

  # Class used by PeerClientHandler to keep track of information associated with a single torrent
  # being downloaded/uploaded.
  class TorrentData
    def initialize(metainfo, trackerClient)
      @metainfo = metainfo
      @trackerClient = trackerClient
      @peerManager = PeerManager.new
      @pieceManagerRequestMetadata = {}
      @bytesDownloaded = 0
      @bytesUploaded = 0
      @peers = PeerHolder.new
      @state = :initializing
      @blockState = nil
    end
    attr_accessor :metainfo
    attr_accessor :trackerClient
    attr_accessor :peers
    attr_accessor :peerManager
    attr_accessor :blockState
    attr_accessor :pieceManager
    attr_accessor :pieceManagerRequestMetadata
    attr_accessor :peerChangeListener
    attr_accessor :bytesDownloaded
    attr_accessor :bytesUploaded
    attr_accessor :state
  end

  # Data about torrents for use by the end user. 
  class TorrentDataDelegate
    def initialize(torrentData)
      @metainfo = torrentData.metainfo
      @bytesUploaded = torrentData.bytesUploaded
      @bytesDownloaded = torrentData.bytesDownloaded
      @completedBytes = torrentData.blockState.nil? ? 0 : torrentData.blockState.completedLength
      # This should really be a copy:
      @completePieceBitfield = torrentData.blockState.nil? ? nil : torrentData.blockState.completePieceBitfield
      buildPeersList(torrentData)
      @downloadRate = @peers.reduce(0){ |memo, peer| memo + peer.uploadRate }
      @uploadRate = @peers.reduce(0){ |memo, peer| memo + peer.downloadRate }
      @downloadRateDataOnly = @peers.reduce(0){ |memo, peer| memo + peer.uploadRateDataOnly }
      @uploadRateDataOnly = @peers.reduce(0){ |memo, peer| memo + peer.downloadRateDataOnly }
      @state = torrentData.state
    end

    attr_reader :metainfo
    attr_reader :downloadRate
    attr_reader :uploadRate
    attr_reader :downloadRateDataOnly
    attr_reader :uploadRateDataOnly
    attr_reader :completedBytes
    attr_reader :peers
    attr_reader :state
    attr_reader :completePieceBitfield
  
    private
    def buildPeersList(torrentData)
      @peers = []
      torrentData.peers.all.each do |peer|
        @peers.push peer.clone
      end
    end
  end

  # This class implements a Reactor Handler object. This Handler implements the PeerClient.
  class PeerClientHandler < QuartzTorrent::Handler
    include QuartzTorrent
  
    def initialize(baseDirectory)
      # Hash of TorrentData objects, keyed by torrent infoHash
      @torrentData = {}

      @baseDirectory = baseDirectory

      @logger = LogManager.getLogger("peerclient")

      # Number of peers we ideally want to try and be downloading/uploading with
      @targetActivePeerCount = 50
      @targetUnchokedPeerCount = 4
      @managePeersPeriod = 10 # Defined in bittorrent spec. Only unchoke peers every 10 seconds.
      @requestBlocksPeriod = 1
      @handshakeTimeout = 1
      @requestTimeout = 60
    end

    attr_reader :torrentData

    # Add a new tracker client. This effectively adds a new torrent to download.
    def addTrackerClient(metainfo, trackerclient)
      raise "There is already a tracker registered for torrent #{bytesToHex(metainfo.infoHash)}" if @torrentData.has_key? metainfo.infoHash
      torrentData = TorrentData.new(metainfo, trackerclient)
      torrentData.pieceManager = QuartzTorrent::PieceManager.new(@baseDirectory, metainfo.info)
      @torrentData[metainfo.infoHash] = torrentData

      # Check the existing pieces of the torrent.
      torrentData.state = :checking_pieces
      @logger.info "Checking pieces of torrent #{bytesToHex(metainfo.infoHash)} asynchronously."
      id = torrentData.pieceManager.findExistingPieces
      torrentData.pieceManagerRequestMetadata[id] = PieceManagerRequestMetadata.new(:check_existing, nil)

      # Schedule checking for PieceManager results
      @reactor.scheduleTimer(@requestBlocksPeriod, [:check_piece_manager, metainfo.infoHash], true, false)
    end

    # Remove a torrent.
    def removeTorrent(infoHash)
      torrentData = @torrentData.delete infoHash
  
      if torrentData    
        torrentData.trackerClient.removePeersChangedListener(torrentData.peerChangeListener)
      end

      # Delete all peers related to this torrent
      # Can't do this right now, since it could be in use by an event handler. Use an immediate, non-recurring timer instead.
      @reactor.scheduleTimer(0, [:removetorrent, infoHash], false, true)
    end

    def serverInit(metadata, addr, port)
      # A peer connected to us
      # Read handshake message
      @logger.warn "Peer connection from #{addr}:#{port}"
      begin
        msg = PeerHandshake.unserializeExceptPeerIdFrom currentIo
      rescue
        @logger.warn "Peer failed handshake: #{$!}"
        close
        return
      end

      torrentData = torrentDataForHandshake(msg, "#{addr}:#{port}")
      # Are we tracking this torrent?
      if !torrentData
        @logger.warn "Peer sent handshake for unknown torrent"
        close
        return 
      end
      trackerclient = torrentData.trackerClient

      # If we already have too many connections, don't allow this connection.
      classifiedPeers = ClassifiedPeers.new torrentData.peers.all
      if classifiedPeers.establishedPeers.length > @targetActivePeerCount
        @logger.warn "Closing connection to peer from #{addr}:#{port} because we already have #{classifiedPeers.establishedPeers.length} active peers which is > the target count of #{@targetActivePeerCount} "
        close
        return 
      end  

      # Send handshake
      outgoing = PeerHandshake.new
      outgoing.peerId = trackerclient.peerId
      outgoing.infoHash = torrentData.metainfo.infoHash
      outgoing.serializeTo currentIo

      # Send extended handshake if the peer supports extensions
      if (msg.reserved.unpack("C8")[5] & 0x10) != 0
        @logger.warn "Peer supports extensions. Sending extended handshake"
        extended = ExtendedHandshake.new
        extended.serializeTo currentIo
      end
 
      # Read incoming handshake's peerid
      msg.peerId = currentIo.read(PeerHandshake::PeerIdLen)

      if msg.peerId == trackerclient.peerId
        @logger.info "We got a connection from ourself. Closing connection."
        close
        return
      end
     
      peer = nil
      peers = torrentData.peers.findById(msg.peerId)
      if peers
        peers.each do |existingPeer|
          if existingPeer.state != :disconnected
            @logger.warn "Peer with id #{msg.peerId} created a new connection when we already have a connection in state #{existingPeer.state}. Closing new connection."
            close
            return
          else
            if existingPeer.trackerPeer.ip == addr && existingPeer.trackerPeer.port == port
              peer = existingPeer
            end
          end
        end
      end

      if ! peer
        peer = Peer.new(TrackerPeer.new(addr, port))
        updatePeerWithHandshakeInfo(torrentData, msg, peer)
        torrentData.peers.add peer
        if ! peers
          @logger.warn "Unknown peer with id #{msg.peerId} connected."
        else
          @logger.warn "Known peer with id #{msg.peerId} connected from new location."
        end
      else
        @logger.warn "Known peer with id #{msg.peerId} connected from known location."
      end

      @logger.info "Peer #{peer} connected to us. "

      peer.state = :established
      peer.amChoked = true
      peer.peerChoked = true
      peer.amInterested = false
      peer.peerInterested = false
      peer.bitfield = Bitfield.new(torrentData.metainfo.info.pieces.length)

      # Send bitfield
      sendBitfield(currentIo, torrentData.blockState.completePieceBitfield) if torrentData.blockState

      setMetaInfo(peer)
    end

    def clientInit(peer)
      # We connected to a peer
      # Send handshake
      torrentData = @torrentData[peer.infoHash]
      if ! torrentData
        @logger.warn "No tracker client found for peer #{peer}. Closing connection."
        close
        return
      end
      trackerclient = torrentData.trackerClient

      @logger.info "Connected to peer #{peer}. Sending handshake."
      msg = PeerHandshake.new
      msg.peerId = trackerclient.peerId
      msg.infoHash = peer.infoHash
      msg.serializeTo currentIo
      peer.state = :handshaking
      @reactor.scheduleTimer(@handshakeTimeout, [:handshake_timeout, peer], false)
      @logger.info "Done sending handshake."

      # Send bitfield
      sendBitfield(currentIo, torrentData.blockState.completePieceBitfield) if torrentData.blockState
    end

    def recvData(peer)
      msg = nil

      @logger.debug "Got data from peer #{peer}"

      if peer.state == :handshaking
        # Read handshake message
        begin
          @logger.debug "Reading handshake from #{peer}"
          msg = PeerHandshake.unserializeFrom currentIo
        rescue
          @logger.warn "Peer #{peer} failed handshake: #{$!}"
          setPeerDisconnected(peer)
          close
          return
        end
      else
        begin
          @logger.debug "Reading wire-message from #{peer}"
          msg = peer.peerMsgSerializer.unserializeFrom currentIo
          #msg = PeerWireMessage.unserializeFrom currentIo
        rescue EOFError
          @logger.info "Peer #{peer} disconnected."
          setPeerDisconnected(peer)
          close
          return
        rescue
          @logger.warn "Unserializing message from peer #{peer} failed: #{$!}"
          @logger.warn $!.backtrace.join "\n"
          setPeerDisconnected(peer)
          close
          return
        end
        peer.updateUploadRate msg
        @logger.info "Peer #{peer} upload rate: #{peer.uploadRate.value}  data only: #{peer.uploadRateDataOnly.value}"
      end


      if msg.is_a? PeerHandshake
        # This is a remote peer that we connected to returning our handshake.
        processHandshake(msg, peer)
        peer.state = :established
        peer.amChoked = true
        peer.peerChoked = true
        peer.amInterested = false
        peer.peerInterested = false
      elsif msg.is_a? BitfieldMessage
        @logger.warn "Received bitfield message from peer."
        handleBitfield(msg, peer)
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
      elsif msg.is_a? Request
        @logger.warn "Received request message from peer for torrent #{bytesToHex(peer.infoHash)}: piece #{msg.pieceIndex} offset #{msg.blockOffset} length #{msg.blockLength}."
        handleRequest(msg, peer)
      elsif msg.is_a? Have
        @logger.warn "Received have message from peer for torrent #{bytesToHex(peer.infoHash)}: piece #{msg.pieceIndex}"
        handleHave(msg, peer)
      elsif msg.is_a? KeepAlive
        @logger.warn "Received keep alive message from peer."
      elsif msg.is_a? ExtendedHandshake
        @logger.warn "Received extended handshake message from peer."
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
      elsif metadata.is_a?(Array) && metadata[0] == :handshake_timeout
        handleHandshakeTimeout(metadata[1])
      elsif metadata.is_a?(Array) && metadata[0] == :removetorrent
        torrentData = @torrentData[metadata[1]]
        if ! torrentData
          @logger.warn "No torrent data found for torrent #{bytesToHex(metadata[1])}."
          return
        end

        # Remove all the peers for this torrent.
        torrentData.peers.all.each do |peer|
          if peer.state != :disconnected
            # Close socket 
            withPeersIo(peer, "when removing torrent") do |io|
              setPeerDisconnected(peer)
              close(io)
            end
          end
          torrentData.peers.delete peer
        end
      elsif metadata.is_a?(Array) && metadata[0] == :get_torrent_data
        @torrentData.each do |k,v|
          begin
            if metadata[3].nil? || k == metadata[3]
              v = TorrentDataDelegate.new(v)
              metadata[1][k] = v
            end
          rescue
            @logger.error "Error building torrent data response for user: #{$!}"
            @logger.error "#{$!.backtrace.join("\n")}"
          end
        end
        metadata[2].signal
      else
        @logger.info "Unknown timer #{metadata} expired."
      end
    end

    def error(peer, details)
      # If a peer closes the connection during handshake before we determine their id, we don't have a completed
      # Peer object yet. In this case the peer parameter is the symbol :listener_socket
      if peer == :listener_socket
        @logger.info "Error with handshaking peer: #{details}. Closing connection."
      else
        @logger.info "Error with peer #{peer}: #{details}. Closing connection."
        setPeerDisconnected(peer)
      end
      # Close connection
      close
    end
    
    # Get a hash of new TorrentDataDelegate objects keyed by torrent infohash.
    # This method is meant to be called from a different thread than the one
    # the reactor is running in. This method is not immediate but blocks until the
    # data is prepared. 
    # If infoHash is passed, only that torrent data is returned (still in a hashtable; just one entry)
    def getDelegateTorrentData(infoHash = nil)
      # Use an immediate, non-recurring timer.
      result = {}
      semaphore = Semaphore.new
      @reactor.scheduleTimer(0, [:get_torrent_data, result, semaphore, infoHash], false, true)
      semaphore.wait
      result
    end

    private
    def setPeerDisconnected(peer)
      peer.state = :disconnected

      torrentData = @torrentData[peer.infoHash]
      # Are we tracking this torrent?
      if torrentData && torrentData.blockState
        # For any outstanding requests, mark that we no longer have requested them
        peer.requestedBlocks.each do |blockIndex, b|
          blockInfo = torrentData.blockState.createBlockinfoByBlockIndex(blockIndex)
          torrentData.blockState.setBlockRequested blockInfo, false
        end
        peer.requestedBlocks.clear
      end

    end

    def processHandshake(msg, peer)
      torrentData = torrentDataForHandshake(msg, peer)
      # Are we tracking this torrent?
      return false if !torrentData

      if msg.peerId == torrentData.trackerClient.peerId
        @logger.info "We connected to ourself. Closing connection."
        peer.isUs = true
        close
        return
      end

      peers = torrentData.peers.findById(msg.peerId)
      if peers
        peers.each do |existingPeer|
          if existingPeer.state == :connected
            @logger.warn "Peer with id #{msg.peerId} created a new connection when we already have a connection in state #{existingPeer.state}. Closing new connection."
            torrentData.peers.delete existingPeer
            setPeerDisconnected(peer)
            close
            return
          end
        end
      end

      trackerclient = torrentData.trackerClient

      updatePeerWithHandshakeInfo(torrentData, msg, peer)
      peer.bitfield = Bitfield.new(torrentData.metainfo.info.pieces.length)

      # Send extended handshake if the peer supports extensions
      if (msg.reserved.unpack("C8")[5] & 0x10) != 0
        @logger.warn "Peer supports extensions. Sending extended handshake"
        extended = ExtendedHandshake.new
        extended.serializeTo currentIo
      end

      true
    end

    def torrentDataForHandshake(msg, peer)
      torrentData = @torrentData[msg.infoHash]
      # Are we tracking this torrent?
      if !torrentData
        if peer.is_a?(Peer)
          @logger.info "Peer #{peer} failed handshake: we are not managing torrent #{bytesToHex(msg.infoHash)}"
          setPeerDisconnected(peer)
        else
          @logger.info "Incoming peer #{peer} failed handshake: we are not managing torrent #{bytesToHex(msg.infoHash)}"
        end
        close
        return nil
      end
      torrentData
    end

    def updatePeerWithHandshakeInfo(torrentData, msg, peer)
      @logger.info "peer #{peer} sent valid handshake for torrent #{bytesToHex(torrentData.metainfo.infoHash)}"
      peer.infoHash = msg.infoHash
      # If this was a peer we got from a tracker that had no id then we only learn the id on handshake.
      peer.trackerPeer.id = msg.peerId
      torrentData.peers.idSet peer
    end

    def handleHandshakeTimeout(peer)
      if peer.state == :handshaking
        @logger.warn "Peer #{peer} failed handshake: handshake timed out after #{@handshakeTimeout} seconds."
        withPeersIo(peer, "handling handshake timeout") do |io|
          setPeerDisconnected(peer)
          close(io)
        end
      end
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
        # Don't treat ourself as a peer.
        next if p.id && p.id == trackerclient.peerId

        if ! torrentData.peers.findByAddr(p.ip, p.port)
          @logger.debug "Adding tracker peer #{p} to peers list"
          peer = Peer.new(p)
          peer.infoHash = infoHash
          torrentData.peers.add peer
        end
      end

      classifiedPeers = ClassifiedPeers.new torrentData.peers.all

      manager = torrentData.peerManager
      if ! manager
        @logger.error "Manage peers: peer manager client for torrent #{bytesToHex(infoHash)} not found."
        return
      end

      toConnect = manager.manageConnections(classifiedPeers)
      toConnect.each do |peer|
        @logger.info "Connecting to peer #{peer}"
        connect peer.trackerPeer.ip, peer.trackerPeer.port, peer
      end

      manageResult = manager.managePeers(classifiedPeers)
      manageResult.unchoke.each do |peer|
        @logger.info "Unchoking peer #{peer}"
        withPeersIo(peer, "unchoking peer") do |io|
          msg = Unchoke.new
          sendMessageToPeer msg, io, peer
          peer.peerChoked = false
        end
      end

      manageResult.choke.each do |peer|
        @logger.info "Choking peer #{peer}"
        withPeersIo(peer, "choking peer") do |io|
          msg = Choke.new
          sendMessageToPeer msg, io, peer
          peer.peerChoked = true
        end
      end

    end

    def requestBlocks(infoHash)
      torrentData = @torrentData[infoHash]
      if ! torrentData
        @logger.error "Request blocks peers: tracker client for torrent #{bytesToHex(infoHash)} not found."
        return
      end

      classifiedPeers = ClassifiedPeers.new torrentData.peers.all

      if ! torrentData.blockState
        @logger.error "Request blocks peers: no blockstate yet."
        return
      end

      # Delete any timed-out requests.
      classifiedPeers.establishedPeers.each do |peer|
        toDelete = []
        peer.requestedBlocks.each do |blockIndex, requestTime|
          toDelete.push blockIndex if (Time.new - requestTime) > @requestTimeout
        end
        toDelete.each do |blockIndex|
          @logger.info "Block #{blockIndex} request timed out."
          blockInfo = torrentData.blockState.createBlockinfoByBlockIndex(blockIndex)
          torrentData.blockState.setBlockRequested blockInfo, false
          peer.requestedBlocks.delete blockIndex
        end
      end

      # Update the allowed pending requests based on how well the peer did since last time.
      classifiedPeers.establishedPeers.each do |peer|
        if peer.requestedBlocksSizeLastPass
          if peer.requestedBlocksSizeLastPass == peer.maxRequestedBlocks
            downloaded = peer.requestedBlocksSizeLastPass - peer.requestedBlocks.size
            if downloaded > peer.maxRequestedBlocks*8/10
              peer.maxRequestedBlocks = peer.maxRequestedBlocks * 12 / 10
            elsif downloaded == 0
              peer.maxRequestedBlocks = peer.maxRequestedBlocks * 8 / 10
            end
            peer.maxRequestedBlocks = 10 if peer.maxRequestedBlocks < 10
          end
        end
      end

      # Request blocks
      blockInfos = torrentData.blockState.findRequestableBlocks(classifiedPeers, 100)
      blockInfos.each do |blockInfo|
        # Pick one of the peers that has the piece to download it from. Pick one of the
        # peers with the top 3 upload rates.
        elegiblePeers = blockInfo.peers.find_all{ |p| p.requestedBlocks.length < p.maxRequestedBlocks }.sort{ |a,b| b.uploadRate.value <=> a.uploadRate.value}
        random = elegiblePeers[rand(blockInfo.peers.size)]
        peer = elegiblePeers.first(3).push(random).shuffle.first
        next if ! peer
        withPeersIo(peer, "requesting block") do |io|
          if ! peer.amInterested
            # Let this peer know that I'm interested if I haven't yet.
            msg = Interested.new
            sendMessageToPeer msg, io, peer
            peer.amInterested = true
          end
          @logger.info "Requesting block from #{peer}: piece #{blockInfo.pieceIndex} offset #{blockInfo.offset} length #{blockInfo.length}"
          msg = blockInfo.getRequest
          sendMessageToPeer msg, io, peer
          torrentData.blockState.setBlockRequested blockInfo, true
          peer.requestedBlocks[blockInfo.blockIndex] = Time.new
        end
      end

      classifiedPeers.establishedPeers.each { |peer| peer.requestedBlocksSizeLastPass = peer.requestedBlocks.length }
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

      if ! torrentData.blockState
        @logger.error "Receive piece: no blockstate yet."
        return
      end

      blockInfo = torrentData.blockState.createBlockinfoByPieceResponse(msg.pieceIndex, msg.blockOffset, msg.data.length)
      if torrentData.blockState.blockCompleted?(blockInfo)
        @logger.info "Receive piece: we already have this block. Ignoring this message."
        return
      end
      peer.requestedBlocks.delete blockInfo.blockIndex
      # Block is marked as not requested when hash is confirmed

      torrentData.bytesDownloaded += msg.data.length
      id = torrentData.pieceManager.writeBlock(msg.pieceIndex, msg.blockOffset, msg.data)
      torrentData.pieceManagerRequestMetadata[id] = PieceManagerRequestMetadata.new(:write, msg)
    end

    def handleRequest(msg, peer)
      if peer.peerChoked
        @logger.warn "Request piece: peer #{peer} requested a block when they are choked."
        return
      end

      torrentData = @torrentData[peer.infoHash]
      if ! torrentData
        @logger.error "Request piece: torrent data for torrent #{bytesToHex(peer.infoHash)} not found."
        return
      end
      if msg.blockLength <= 0
        @logger.error "Request piece: peer requested block of length #{msg.blockLength} which is invalid."
        return
      end

      id = torrentData.pieceManager.readBlock(msg.pieceIndex, msg.blockOffset, msg.blockLength)
      torrentData.pieceManagerRequestMetadata[id] = PieceManagerRequestMetadata.new(:read, ReadRequestMetadata.new(peer,msg))
    end

    def handleBitfield(msg, peer)
      torrentData = @torrentData[peer.infoHash]
      if ! torrentData
        @logger.error "Bitfield: torrent data for torrent #{bytesToHex(peer.infoHash)} not found."
        return
      end

      peer.bitfield = Bitfield.new(torrentData.metainfo.info.pieces.length)
      peer.bitfield.copyFrom(msg.bitfield)

      if ! torrentData.blockState
        @logger.error "Bitfield: no blockstate yet."
        return
      end

      # If we are interested in something from this peer, let them know.
      needed = torrentData.blockState.completePieceBitfield.compliment
      needed.intersection!(peer.bitfield)
      if ! needed.allClear?
        if ! peer.amInterested
          @logger.info "Need some pieces from peer #{peer} so sending Interested message"
          msg = Interested.new
          sendMessageToPeer msg, currentIo, peer
          peer.amInterested = true
        end
      end
    end

    def handleHave(msg, peer)
      torrentData = @torrentData[peer.infoHash]
      if ! torrentData
        @logger.error "Have: torrent data for torrent #{bytesToHex(peer.infoHash)} not found."
        return
      end

      if msg.pieceIndex >= torrentData.metainfo.info.pieces.length
        @logger.warn "Peer #{peer} sent Have message with invalid piece index"
        return
      end

      # Update peer's bitfield
      peer.bitfield.set msg.pieceIndex

      if ! torrentData.blockState
        @logger.error "Have: no blockstate yet."
        return
      end

      # If we are interested in something from this peer, let them know.
      if ! torrentData.blockState.completePieceBitfield.set?(msg.pieceIndex)
        @logger.info "Peer #{peer} just got a piece we need so sending Interested message"
        msg = Interested.new
        sendMessageToPeer msg, currentIo, peer
        peer.amInterested = true
      end
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
        metaData = torrentData.pieceManagerRequestMetadata.delete(result.requestId)
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
        elsif metaData.type == :read
          if result.successful?
            readRequestMetadata = metaData.data
            peer = readRequestMetadata.peer
            withPeersIo(peer, "sending piece message") do |io|
              msg = Piece.new
              msg.pieceIndex = readRequestMetadata.requestMsg.pieceIndex
              msg.blockOffset = readRequestMetadata.requestMsg.blockOffset
              msg.data = result.data
              sendMessageToPeer msg, io, peer
              torrentData.bytesUploaded += msg.data.length
              @logger.info "Sending piece to peer"
            end
          else
            @logger.error "Reading block failed: #{result.error}"
          end
        elsif metaData.type == :hash
          if result.successful?
            @logger.info "Hash of piece #{metaData.data} is correct"
            sendHaves(torrentData, metaData.data)
            sendUninterested(torrentData)
          else
            @logger.info "Hash of piece #{metaData.data} is incorrect. Marking piece as not complete."
            torrentData.blockState.setPieceCompleted metaData.data, false
          end
        elsif metaData.type == :check_existing
          handleCheckExistingResult(torrentData, result)
        end
      end
    end

    def handleCheckExistingResult(torrentData, pieceManagerResult)
      if pieceManagerResult.successful?
        existingBitfield = pieceManagerResult.data
        @logger.info "We already have #{existingBitfield.countSet}/#{existingBitfield.length} pieces." 

        metaInfo = torrentData.metainfo
       
        torrentData.blockState = BlockState.new(metaInfo, existingBitfield)

        @logger.info "Starting torrent #{bytesToHex(metaInfo.infoHash)}. Information:"
        @logger.info "  piece length:     #{metaInfo.info.pieceLen}"
        @logger.info "  number of pieces: #{metaInfo.info.pieces.size}"
        @logger.info "  total length      #{metaInfo.info.dataLength}"

        # Add a listener for when the tracker's peers change.
        torrentData.peerChangeListener = Proc.new do 
          @logger.info "Managing peers for torrent #{bytesToHex(metaInfo.infoHash)} on peer change event"

          # Non-recurring and immediate timer
          @reactor.scheduleTimer(@managePeersPeriod, [:manage_peers, metaInfo.infoHash], false, true)
        end
        torrentData.trackerClient.addPeersChangedListener torrentData.peerChangeListener

        # Schedule peer connection management. Recurring and not immediate 
        @reactor.scheduleTimer(@managePeersPeriod, [:manage_peers, metaInfo.infoHash], true, false)
        # Schedule requesting blocks from peers. Recurring and not immediate
        @reactor.scheduleTimer(@requestBlocksPeriod, [:request_blocks, metaInfo.infoHash], true, false)
        torrentData.state = :running
        
      else
        @logger.info "Checking existing pieces of torrent #{bytesToHex(torrentData.metainfo.infoHash)} failed: #{pieceManagerResult.error}"
        torrentData.state = :error
      end
    end

    # Find the io associated with the peer and yield it to the passed block.
    # If no io is found an error is logged.
    #
    def withPeersIo(peer, what = nil)
      io = findIoByMetainfo(peer)
      if io
        yield io
      else
        s = ""
        s = "when #{what}" if what
        @logger.warn "Couldn't find the io for peer #{peer} #{what}"
      end
    end

    def sendBitfield(io, bitfield)
      set = bitfield.countSet
      if set > 0
        @logger.info "Sending bitfield with #{set} bits set of size #{bitfield.length}."
        msg = BitfieldMessage.new
        msg.bitfield = bitfield
        msg.serializeTo io
      end
    end

    def sendHaves(torrentData, pieceIndex)
      @logger.info "Sending Have messages to all connected peers for piece #{pieceIndex}"
      torrentData.peers.all.each do |peer|
        next if peer.state != :established
        withPeersIo(peer, "when sending Have message") do |io|
          msg = Have.new
          msg.pieceIndex = pieceIndex
          sendMessageToPeer msg, io, peer
        end
      end
    end

    def sendUninterested(torrentData)
      # If we are no longer interested in peers once this piece has been completed, let them know
      return if ! torrentData.blockState
      needed = torrentData.blockState.completePieceBitfield.compliment
      
      classifiedPeers = ClassifiedPeers.new torrentData.peers.all
      classifiedPeers.establishedPeers.each do |peer|
        # Don't bother sending uninterested message if we are already uninterested.
        next if ! peer.amInterested
        needFromPeer = needed.intersection(peer.bitfield)
        if needFromPeer.allClear?
          withPeersIo(peer, "when sending Uninterested message") do |io|
            msg = Uninterested.new
            sendMessageToPeer msg, io, peer
            peer.amInterested = false
            @logger.info "Sending Uninterested message to peer #{peer}"
          end
        end
      end
    end

    def sendMessageToPeer(msg, io, peer)
      peer.updateDownloadRate(msg)
      peer.peerMsgSerializer.serializeTo(msg, io)
      msg.serializeTo io
    end
  end

  # Represents a client that talks to bittorrent peers. This is the main class used to download and upload
  # bittorrents.
  class PeerClient 

    # Create a new PeerClient that will store torrents udner the specified baseDirectory.
    def initialize(baseDirectory)
      @port = 9998
      @handler = nil
      @stopped = true
      @reactor = nil
      @logger = LogManager.getLogger("peerclient")
      @worker = nil
      @handler = PeerClientHandler.new baseDirectory
      @reactor = QuartzTorrent::Reactor.new(@handler, LogManager.getLogger("peerclient.reactor"))
      @toStart = []
    end

    attr_accessor :port

    # Start the PeerClient: open the listening port, and start a new thread to begin downloading/uploading pieces.
    def start 
      @reactor.listen("0.0.0.0",@port,:listener_socket)

      @stopped = false
      @worker = Thread.new do
        initThread("peerclient")
        @toStart.each{ |trackerclient| trackerclient.start }
        @reactor.start 
        @logger.info "Reactor stopped."
        @handler.torrentData.each do |k,v|
          v.trackerClient.stop
        end 
      end
    end

    # Stop the PeerClient. This method may take some time to complete.
    def stop
      @logger.info "Stop called. Stopping reactor"
      @reactor.stop
      if @worker
        @logger.info "Worker wait timed out after 10 seconds. Shutting down anyway" if ! @worker.join(10)
      end
    end

    # Add a new torrent to manage.
    def addTorrentByMetainfo(metainfo)
      trackerclient = TrackerClient.createFromMetainfo(metainfo, false)
      trackerclient.port = @port
      @handler.addTrackerClient(metainfo, trackerclient)

      trackerclient.dynamicRequestParamsBuilder = Proc.new do
        torrentData = @handler.torrentData[metainfo.infoHash]
        result = TrackerDynamicRequestParams.new(metainfo.info.dataLength)
        if torrentData && torrentData.blockState
          result.left = torrentData.blockState.totalLength - torrentData.blockState.completedLength
          result.downloaded = torrentData.bytesDownloaded
          result.uploaded = torrentData.bytesUploaded
        end
        result
      end

      # If we haven't started yet then add this trackerclient to a queue of 
      # trackerclients to start once we are started. If we start too soon we 
      # will connect to the tracker, and it will try to connect back to us before we are listening.
      if ! trackerclient.started?
        if @stopped
          @toStart.push trackerclient
        else
          trackerclient.start 
        end
      end
    end

    # Get a hash of new TorrentDataDelegate objects keyed by torrent infohash. This is the method to 
    # call to get information about the state of torrents being downloaded.
    def torrentData(infoHash = nil)
      # This will have to work by putting an event in the handler's queue, and blocking for a response.
      # The handler will build a response and return it.
      @handler.getDelegateTorrentData(infoHash)
    end
    

  end
end

