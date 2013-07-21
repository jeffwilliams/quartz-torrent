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
      @uploadRate = 0
      @bitfield = nil
      @firstEstablishTime = nil
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

    # Upload rate of peer to us.
    attr_accessor :uploadRate

    attr_accessor :bitfield

    def to_s
      @trackerPeer.to_s
    end

    # Add a proc to the list of state change listeners.
    def self.addStateChangeListener(l)
      @@stateChangeListeners.push l
    end

    def eql?(o) 
      trackerPeer.eql?(o)
    end
  end
end
