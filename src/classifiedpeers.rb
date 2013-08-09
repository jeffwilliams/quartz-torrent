module QuartzTorrent
  # Torrent peers classified by connection state. 
  class ClassifiedPeers
    # Pass a list of Peer objects for a specific torrent
    def initialize(peers)
      # Classify peers by state
      @disconnectedPeers = []
      @handshakingPeers = []
      @establishedPeers = []
      @interestedPeers = []
      @uninterestedPeers = []
      @chokedInterestedPeers = []
      @chokedUninterestedPeers = []
      @unchokedInterestedPeers = []
      @unchokedUninterestedPeers = []
      @requestablePeers = []

      peers.each do |peer|

        # If we come across ourself, ignore it.
        next if peer.isUs

        if peer.state == :disconnected
          @disconnectedPeers.push peer
        elsif peer.state == :handshaking
          @handshakingPeers.push peer
        elsif peer.state == :established
          @establishedPeers.push peer
          if peer.peerChoked
            if peer.peerInterested
              @chokedInterestedPeers.push peer
              @interestedPeers.push peer
            else
              @chokedUninterestedPeers.push peer
              @uninterestedPeers.push peer
            end
          else
            if peer.peerInterested
              @unchokedInterestedPeers.push peer
              @interestedPeers.push peer
            else
              @unchokedUninterestedPeers.push peer
              @uninterestedPeers.push peer
            end
          end

          if !peer.amChoked
            @requestablePeers.push peer
          end
        end
      end
    end

    # Peers that are disconnected. Either they have never been connected to, or 
    # they were connected to and have been disconnected.
    attr_accessor :disconnectedPeers
    
    # Peers still performing a handshake.
    attr_accessor :handshakingPeers
    
    # Peers with an established connection. This is the union of
    # chokedInterestedPeers, chokedUninterestedPeers, and unchokedPeers.
    attr_accessor :establishedPeers

    # Peers that we have an established connection to, and are choked but are interested. 
    attr_accessor :chokedInterestedPeers

    # Peers that we have an established connection to, and are choked and are not interested. 
    attr_accessor :chokedUninterestedPeers

    # Peers that we have an established connection to, and are not choked and are interested.
    attr_accessor :unchokedInterestedPeers

    # Peers that we have an established connection to, and are not choked and are not interested.
    attr_accessor :unchokedUninterestedPeers

    # Peers that we have an established connection to, and are interested
    attr_accessor :interestedPeers

    attr_accessor :uninterestedPeers
      
    # Peers that we have an established connection to, that are not choking us, that we are interested in
    attr_accessor :requestablePeers

    def to_s
      s = ""
      s << "  Choked and interested #{chokedInterestedPeers.inspect}"
      s << "  Choked and uninterested #{chokedUninterestedPeers.inspect}"
      s << "  Unchoked and interested #{unchokedInterestedPeers.inspect}"
      s << "  Unchoked and uninterested #{unchokedUninterestedPeers.inspect}"
      s  
    end
  end
end
