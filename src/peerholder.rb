require './src/peer.rb'
require 'src/util'

module QuartzTorrent
  class PeerHolder
    def initialize
      @peersById = {}
      @peersByAddr = {}
      @peersByInfoHash = {}
      @log = LogManager.getLogger("peerholder")
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

      # Do not add if peer is already present by address
      if @peersByAddr.has_key?(byAddrKey(peer))
        @log.debug "Not adding peer #{peer} since it already exists by #{@peersById.has_key?(peer.trackerPeer.id) ? "id" : "addr"}."
        return
      end

      if peer.trackerPeer.id
        @peersById.pushToList(peer.trackerPeer.id, peer)
        
        # If id is null, this is probably a peer received from the tracker that has no ID.
      end

      @peersByAddr[byAddrKey(peer)] = peer

      @peersByInfoHash.pushToList(peer.infoHash, peer)
    end

    # This peer, which previously had no id, has finished handshaking and now has an ID.
    def idSet(peer)
      @peersById.each do |e| 
        return if e.eql?(peer)
      end
      @peersById.pushToList(peer.trackerPeer.id, peer)
    end

    def delete(peer)
      @peersByAddr.delete byAddrKey(peer)

      list = @peersByInfoHash[peer.infoHash]
      if list
        list.collect! do |p|
          if !p.eql?(peer)
            peer
          else
            nil
          end
        end
        list.compact!
      end

      if peer.trackerPeer.id
        list = @peersById[peer.trackerPeer.id]
        if list
          list.collect! do |p|
            if !p.eql?(peer)
              peer
            else
              nil
            end
          end
          list.compact!
        end
      end
    end

    def all
      @peersByAddr.values
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
