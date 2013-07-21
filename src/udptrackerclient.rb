module QuartzTorrent
  # A tracker client that uses the UDP protocol as defined by http://xbtt.sourceforge.net/udp_tracker_protocol.html
  class UdpTrackerClient < TrackerClient
    # Set UDP receive length to a value that allows up to 100 peers to be returned in an announce.
    ReceiveLength = 620 
    def initialize(metainfo)
      super()
      @metainfo = metainfo
      if metainfo.announce =~ /udp:\/\/([^:]+):(\d+)/
        @host = $1
        @port = $2
      else
        throw "UDP Tracker announce URL is invalid: #{metainfo.announce}"
      end
    end

    def request(event = nil)
      if event == :started
        event = UdpTrackerMessage::EventStarted
      elsif event == :stopped
        event = UdpTrackerMessage::EventStopped
      elsif event == :completed
        event = UdpTrackerMessage::EventCompleted
      else
        event = UdpTrackerMessage::EventNone
      end

      socket = UDPSocket.new
      socket.connect @host, @port

      # Send connect request
      req = UdpTrackerConnectRequest.new
      socket.send req.serialize, 0
      resp = UdpTrackerConnectResponse.unserialize(socket.recvfrom(ReceiveLength)[0])
      raise "Invalid connect response: response transaction id is different from the request transaction id" if resp.transactionId != req.transactionId
      connectionId = resp.connectionId

      # Send announce request      
      req = UdpTrackerAnnounceRequest.new(connectionId)
      req.peerId = @peerId
      req.infoHash = @metainfo.infoHash
      req.downloaded = 0
      req.left = @metainfo.info.totalLength.to_i
      req.uploaded = 0
      req.event = event
      req.port = socket.addr[1]
      socket.send req.serialize, 0
      resp = UdpTrackerAnnounceResponse.unserialize(socket.recvfrom(ReceiveLength)[0])
      socket.close

      peers = []
      resp.ips.length.times do |i|
        ip = resp.ips[i].unpack("CCCC").join('.')
        port = resp.ports[i].unpack("n").first
        peers.push TrackerPeer.new ip, port
      end
      peers

      result = TrackerResponse.new(true, nil, peers)
      result.interval = resp.interval if resp.interval
      result
    end
  end

end
