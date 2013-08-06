require './src/classifiedpeers.rb'

module QuartzTorrent
  class ManagePeersResult
    def initialize
      @unchoke = []
      @choke = []
    end

    # List of peers to unchoke
    attr_accessor :unchoke
    # List of peers to choke
    attr_accessor :choke

    def to_s
      s = "Peers to unchoke: "
      s << unchoke.collect{ |p| p.nil? ? "'nil'" : "'#{p}'" }.join(" ")
      s << "\n"
      s << "Peers to choke: "
      s << choke.collect{ |p| p.nil? ? "'nil'" : "'#{p}'" }.join(" ")
      s << "\n"
    end
  end

  # This class is used internally by PeerClient (The bittorrent protocol object) to 
  # choke, unchoke, and connect to peers for a specific torrent. 
  class PeerManager

    def initialize
      @logger = LogManager.getLogger("peer_manager")
      @targetActivePeerCount  = 50
      @targetUnchokedPeerCount = 4
      @cachedHandshakingAndEstablishedCount = 0
      # An array of Peers that we are allowing to download.
      @downloaders = []
      @optimisticUnchokePeer = nil
      # A peer is considered newly connected when the number of seconds it has had it's connection established
      # is below this number.
      @newlyConnectedDuration = 60
      @optimisticPeerChangeDuration = 30
      @lastOptimisticPeerChangeTime = nil
    end

    # Determine if we need to connect to more peers.
    # Returns a list of peers to connect to.
    def manageConnections(classifiedPeers)

      n = classifiedPeers.handshakingPeers.size + classifiedPeers.establishedPeers.size
      if n < @targetActivePeerCount
        result = classifiedPeers.disconnectedPeers.shuffle.first(@targetActivePeerCount - n)
        @logger.debug "There are #{n} peers connected or in handshaking. Will establish #{result.size} more connections to peers."
        result
      else
        []
      end
    end 

    # Given a list of Peer objects (torrent peers), calculate the actions to
    # take.
    def managePeers(classifiedPeers)
      result = ManagePeersResult.new

      @logger.debug "Manage peers: #{classifiedPeers.disconnectedPeers.size} disconnected, #{classifiedPeers.handshakingPeers.size} handshaking, #{classifiedPeers.establishedPeers.size} established"
      @logger.debug "Manage peers: #{classifiedPeers}"

      # Unchoke some peers. According to the specification:
      #
      # "...unchoking the four peers which have the best upload rate and are interested.  These four peers are referred to as downloaders, because they are interested in downloading from the client."
      # "Peers which have a better upload rate (as compared to the downloaders) but aren't interested get unchoked. If they become interested, the downloader with the worst upload rate gets choked. 
      # If a client has a complete file, it uses its upload rate rather than its download rate to decide which peers to unchoke."
      # "at any one time there is a single peer which is unchoked regardless of its upload rate (if interested, it counts as one of the four allowed downloaders). Which peer is optimistically 
      # unchoked rotates every 30 seconds. Newly connected peers are three times as likely to start as the current optimistic unchoke as anywhere else in the rotation. This gives them a decent chance 
      # of getting a complete piece to upload."
      #
      # This doesn't define initial rampup; On rampup we have no peer upload rate information. 

      # We want to end up with:
      #   - At most 4 peers that are both interested and unchoked. These are Downloaders. They should be the ones with 
      #     the best upload rate.
      #   - All peers that have a better upload rate than Downloaders and are not interested are unchoked. 
      #   - One random peer that is unchoked. If it is interested, it is one of the 4 downloaders. 
      #       When choosing this random peer, peers that have connected in the last N seconds should be 3 times more 
      #       likely to be chosen. This peer only changes every 30 seconds.

      # Step 1: Pick the optimistic unchoke peer 

      selectOptimisticPeer(classifiedPeers)

      # Step 2: Update the downloaders to be the interested peers with the best upload rate.

      if classifiedPeers.interestedPeers.size > 0
        bestUploadInterested = classifiedPeers.interestedPeers.sort{ |a,b| a.uploadRate.value <=> b.uploadRate.value}.first(@targetUnchokedPeerCount)

        # If the optimistic unchoke peer is interested, he counts as a downloader.
        if @optimisticUnchokePeer && @optimisticUnchokePeer.peerInterested
          peerAlreadyIsDownloader = false
          bestUploadInterested.each do |peer|
            if peer.eql?(@optimisticUnchokePeer)
              peerAlreadyIsDownloader = true
              break
            end
          end
          bestUploadInterested[bestUploadInterested.size-1] = @optimisticUnchokePeer if ! peerAlreadyIsDownloader
        end

        # If one of the downloaders has changed, choke the peer
        downloadersMap = {}
        @downloaders.each{ |d| downloadersMap[d.trackerPeer] = d }
        bestUploadInterested.each do |peer|
          if downloadersMap.delete peer.trackerPeer
            # This peer was already a downloader. No changes.
          else
            # This peer wasn't a downloader before. Now it is; unchoke it
            result.unchoke.push peer if peer.peerChoked
          end
        end
        # Any peers remaining in the map are no longer a downloader. Choke them.
        result.choke = result.choke.concat(downloadersMap.values)
    
        @downloaders = bestUploadInterested
      end

      # Step 3: Unchoke all peers that have a better upload rate but are not interested.
      if classifiedPeers.uninterestedPeers.size > 0
        classifiedPeers.uninterestedPeers.each do |peer|
          if @downloaders.size > 0
            if peer.uploadRate.value > @downloaders[0].uploadRate.value && peer.peerChoked
              result.unchoke.push peer
            end
            if peer.uploadRate.value < @downloaders[0].uploadRate.value && ! peer.peerChoked && ! peer.eql?(@optimisticUnchokePeer)
              result.choke.push peer
            end
          else
            result.unchoke.push peer if peer.peerChoked
          end
        end
      end

      @logger.debug "Manage peers result: #{result}"

      result
    end

    private
    def selectOptimisticPeer(classifiedPeers)
      # "at any one time there is a single peer which is unchoked regardless of its upload rate (if interested, it counts as one of the four allowed downloaders). Which peer is optimistically 
      # unchoked rotates every 30 seconds. Newly connected peers are three times as likely to start as the current optimistic unchoke as anywhere else in the rotation. This gives them a decent chance 
      # of getting a complete piece to upload."

      if !@lastOptimisticPeerChangeTime || (Time.new - @lastOptimisticPeerChangeTime > @optimisticPeerChangeDuration)
        list = []
        classifiedPeers.establishedPeers.each do |peer| 
          if (Time.new - peer.firstEstablishTime) < @newlyConnectedDuration
            3.times{ list.push peer }
          else
            list.push peer
          end
        end
        @optimisticUnchokePeer = list[rand(list.size)]
        if @optimisticUnchokePeer
          @logger.info "Optimistically unchoked peer set to #{@optimisticUnchokePeer.trackerPeer}"
          @lastOptimisticPeerChangeTime = Time.new
        end
      end
    end
  end
end
