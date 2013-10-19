require 'quartz_torrent/rate'
require 'quartz_torrent/peermsgserialization'

module QuartzTorrent
  # This class represents a torrent peer. 
  class Peer
    @@stateChangeListeners = []

    # Create a new Peer using the information from the passed TrackerPeer object.
    def initialize(trackerPeer)
      @trackerPeer = trackerPeer
      @amChoked = true
      @amInterested = false
      @peerChoked = true
      @peerInterested = false
      @infoHash = nil
      @state = :disconnected
      @uploadRate = Rate.new
      @downloadRate = Rate.new
      @uploadRateDataOnly = Rate.new
      @downloadRateDataOnly = Rate.new
      @bitfield = nil
      @firstEstablishTime = nil
      @isUs = false
      @requestedBlocks = {}
      @requestedBlocksSizeLastPass = nil
      @maxRequestedBlocks = 50
      @peerMsgSerializer = PeerWireMessageSerializer.new
    end

    # A TrackerPeer class with the information about the peer retrieved from
    # the tracker. When initially created the trackerPeer.id property may be null, 
    # but once the peer has connected it is set.
    attr_accessor :trackerPeer

    # Am I choked by this peer
    attr_accessor :amChoked
    # Am I interested in this peer
    attr_accessor :amInterested
  
    # This peer is choked by me
    attr_accessor :peerChoked
    # Is this peer interested
    attr_accessor :peerInterested

    # Info hash for the torrent of this peer 
    attr_accessor :infoHash

    # Time when the peers connection was established the first time.
    # This is nil when the peer has never had an established connection.
    attr_accessor :firstEstablishTime

    # Maximum number of outstanding block requests allowed for this peer.
    attr_accessor :maxRequestedBlocks

    # Peer connection state.
    # All peers start of in :disconnected. When trying to handshake, 
    # they are in state :handshaking. Once handshaking is complete and we can 
    # send/accept requests, the state is :established.
    attr_reader :state
    def state=(state)
      oldState = @state
      @state = state
      @@stateChangeListeners.each{ |l| l.call(self, oldState, @state) }
      @firstEstablishTime = Time.new if @state == :established && ! @firstEstablishTime
    end

    # Is this peer ourself? Used to tell if we connected to ourself.
    attr_accessor :isUs

    # Upload rate of peer to us.
    attr_accessor :uploadRate
    # Download rate of us to peer.
    attr_accessor :downloadRate

    # Upload rate of peer to us, only counting actual torrent data
    attr_accessor :uploadRateDataOnly
    # Download rate of us to peer, only counting actual torrent data
    attr_accessor :downloadRateDataOnly

    # A Bitfield representing the pieces that the peer has.
    attr_accessor :bitfield

    # A hash of the block indexes of the outstanding blocks requested from this peer
    attr_accessor :requestedBlocks
    attr_accessor :requestedBlocksSizeLastPass

    # A PeerWireMessageSerializer that can unserialize and serialize messages to and from this peer.
    attr_accessor :peerMsgSerializer

    # Return a string representation of the peer.
    def to_s
      @trackerPeer.to_s
    end

    # Add a proc to the list of state change listeners.
    def self.addStateChangeListener(l)
      @@stateChangeListeners.push l
    end

    # Equate peers.
    def eql?(o)
      o.is_a?(Peer) && trackerPeer.eql?(o.trackerPeer)
    end

    # Update the upload rate of the peer from the passed PeerWireMessage.
    def updateUploadRate(msg)
      @uploadRate.update msg.length
      if msg.is_a? Piece
        @uploadRateDataOnly.update msg.data.length
      end
    end

    # Update the download rate of the peer from the passed PeerWireMessage.
    def updateDownloadRate(msg)
      @downloadRate.update msg.length
      if msg.is_a? Piece
        @downloadRateDataOnly.update msg.data.length
      end
    end

    # Create a clone of this peer. This method does not clone listeners.
    def clone
      peer = Peer.new(@trackerPeer)
      peer.amChoked = amChoked
      peer.amInterested = amInterested
      peer.peerChoked = peerChoked
      peer.peerInterested = peerInterested
      peer.firstEstablishTime = firstEstablishTime
      peer.state = state
      peer.isUs = isUs
      # Take the values of the rates. This is so that if the caller doesn't read the rates
      # in a timely fashion, they don't decay.
      peer.uploadRate = uploadRate.value
      peer.downloadRate = downloadRate.value
      peer.uploadRateDataOnly = uploadRateDataOnly.value
      peer.downloadRateDataOnly = downloadRateDataOnly.value
      if bitfield
        peer.bitfield = Bitfield.new(bitfield.length)
        peer.bitfield.copyFrom bitfield
      end
      peer.requestedBlocks = requestedBlocks.clone
      peer.maxRequestedBlocks = maxRequestedBlocks
      peer.peerMsgSerializer = peerMsgSerializer

      peer
    end
  end
end
