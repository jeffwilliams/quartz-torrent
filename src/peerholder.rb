require './src/peer.rb'

module QuartzTorrent
  class PeerHolder
    def initialize
      @peersById = {}
      @peersByAddr = {}
      @peersByInfoHash = {}
    end

    def findById(peerId)
      @peersById[peerId]
    end

    def findByAddr(ip, port)
      @peersByAddr[ip + port.to_s]
    end

    def findByInfoHash(infoHash)
      l = @peersByInfoHash[infoHash]
      l = [] if ! l
      l
    end

    def add(peer)
      raise "Peer must have it's infoHash set." if ! peer.infoHash

      # Do not add if peer is already present by id OR address
      return if @peersById.has_key?(peer.trackerPeer.id) || @peersByAddr.has_key?(byAddrKey(peer))

      if peer.trackerPeer.id
        @peersById[peer.trackerPeer.id] = peer
        # If id is null, this is probably a peer received from the tracker that has no ID.
      end
      @peersByAddr[byAddrKey(peer)] = peer
      list =  @peersByInfoHash[peer.infoHash]
      if ! list
        list = []
        @peersByInfoHash[peer.infoHash] = list
      end
      list.push peer
    end

    # This peer, which previously had no id, has finished handshaking and now has an ID.
    def idSet(peer)
      @peersById[peer.trackerPeer.id] = peer
    end

    def deleteById(peerId)
      raise "Asked to delete a peer by id, but the peer's id is nil" if ! peerId

      peer = @peersById[peerId]
      if peer
        @peersById.delete peer
        @peersByAddr.delete byAddrKey(peer)
        list = @peersByInfoHash[peer.infoHash]
        if list
          list.collect! do |peer|
            if peer.trackerPeer.id != peerId
              peer 
            else
              nil
            end
          end
          list.compact!
        end
      end
    end

    def to_s(infoHash)
      def makeFlags(peer)
        s = "["
        s << "c" if peer.amChoked
        s << "i" if peer.peerInterested
        s << "C" if peer.peerChoked
        s << "I" if peer.amInterested
        s << "]"
        s
      end    

      s = "Peers: \n"
      peers = @peersByInfoHash[infoHash]
      if peers
        peers.each do |peer|
          s << "  #{peer.to_s} #{makeFlags(peer)}\n"
        end
      end
      s 
    end

    private
    def byAddrKey(peer)
      peer.trackerPeer.ip + peer.trackerPeer.port.to_s
    end
  end
end
