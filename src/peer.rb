require 'src/rate'

module QuartzTorrent
  class Peer
    @@stateChangeListeners = []

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

    attr_accessor :bitfield

    def to_s
      @trackerPeer.to_s
    end

    # Add a proc to the list of state change listeners.
    def self.addStateChangeListener(l)
      @@stateChangeListeners.push l
    end

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
  end
end
