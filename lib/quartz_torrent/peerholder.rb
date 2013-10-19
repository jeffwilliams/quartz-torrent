require 'quartz_torrent/peer.rb'
require 'quartz_torrent/util'

module QuartzTorrent
  # A container class for holding torrent peers. Allows lookup by different properties.
  class PeerHolder
    def initialize
      @peersById = {}
      @peersByAddr = {}
      @peersByInfoHash = {}
      @log = LogManager.getLogger("peerholder")
    end

    # Find a peer by its trackerpeer's peerid. This is the id returned by the tracker, and may be nil.
    def findById(peerId)
      @peersById[peerId]
    end

    # Find a peer by its IP address and port.
    def findByAddr(ip, port)
      @peersByAddr[ip + port.to_s]
    end

    # Find all peers related to the torrent with the passed infoHash.
    def findByInfoHash(infoHash)
      l = @peersByInfoHash[infoHash]
      l = [] if ! l
      l
    end

    # Add a peer to the PeerHolder.
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

    # Set the id for a peer. This peer, which previously had no id, has finished handshaking and now has an ID.
    def idSet(peer)
      @peersById.each do |e| 
        return if e.eql?(peer)
      end
      @peersById.pushToList(peer.trackerPeer.id, peer)
    end

    # Delete the specified peer from the PeerHolder.
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

    # Return the list of all peers.
    def all
      @peersByAddr.values
    end

    # Return the number of peers in the holder.
    def size
      @peersByAddr.size
    end

    # Output a string representation of the PeerHolder, for debugging purposes.
    def to_s(infoHash = nil)
      def makeFlags(peer)
        s = "["
        s << "c" if peer.amChoked
        s << "i" if peer.peerInterested
        s << "C" if peer.peerChoked
        s << "I" if peer.amInterested
        s << "]"
        s
      end    

      if infoHash
        s = "Peers: \n"
        peers = @peersByInfoHash[infoHash]
        if peers
          peers.each do |peer|
            s << "  #{peer.to_s} #{makeFlags(peer)}\n"
          end
        end
      else
        "PeerHolder"
      end
      s 
    end

    private
    def byAddrKey(peer)
      peer.trackerPeer.ip + peer.trackerPeer.port.to_s
    end
  end
end
