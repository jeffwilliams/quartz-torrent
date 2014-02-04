module QuartzTorrent
  class TrackerClient
  end
  class TrackerDriver
  end

  # A tracker driver that uses the HTTP protocol. This is the classic BitTorrent tracker protocol.
  class HttpTrackerDriver < TrackerDriver
    def initialize(announceUrl, infoHash)
      super()
      @startSent = false
      @logger = LogManager.getLogger("http_tracker_client")
      @announceUrl = announceUrl
      @infoHash = infoHash
    end
 
    # Request a list of peers from the tracker and return it as a TrackerResponse.   
    # Event, if specified, may be set to :started, :stopped, or :completed.
    # This is used to notify the tracker that this is the first request,
    # that we are shutting down, or that we have the full torrent respectively.
    # Not specifying the event just means this is a regular poll.
    #def getPeers(event = nil)
    def request(event = nil)

      uri = URI(@announceUrl)
  
      dynamicParams = @dynamicRequestParamsBuilder.call

      params = {}
      params['info_hash'] = CGI.escape(@infoHash)
      params['peer_id'] = dynamicParams.peerId
      params['port'] = dynamicParams.port
      params['uploaded'] = dynamicParams.uploaded.to_s
      params['downloaded'] = dynamicParams.downloaded.to_s
      params['left'] = dynamicParams.left.to_s
      params['compact'] = "1"
      params['no_peer_id'] = "1"
      if ! @startSent
        event = :started  
        @startSent = true
      end
      params['event'] = event.to_s if event
      

      @logger.debug "Request parameters: "
      params.each do |k,v|
        @logger.debug "  #{k}: #{v}"
      end

      query = ""
      params.each do |k,v|
        query  << "&" if query.length > 0
        query  << "#{k}=#{v}"
      end
      uri.query = query
  
      res = Net::HTTP.get_response(uri)
      @logger.debug "Tracker response code: #{res.code}"
      @logger.debug "Tracker response body: #{res.body}"
      result = buildTrackerResponse(res)
      @logger.debug "TrackerResponse: #{result.inspect}"
      result 
    end

    protected
    def decodePeers(peersProp)
      peers = []
      if peersProp.is_a?(String)
        # Compact format: 4byte IP followed by 2byte port, in network byte order 
        index = 0
        while index + 6 <= peersProp.length
          ip = peersProp[index,4].unpack("CCCC").join('.')
          port = peersProp[index+4,2].unpack("n").first
          peers.push TrackerPeer.new(ip, port)
          index += 6
        end
      else 
        # Non-compact format
        peersProp.each do |peer|
          ip = peer['ip'] 
          port = peer['port'] 
          if ip && port
            peers.push TrackerPeer.new(ip, port)
          end
        end
        #raise "Non-compact peer format not implemented"
      end
      peers
    end

    private
    def buildTrackerResponse(netHttpResponse)
      error = nil
      peers = []
      interval = nil
      success = netHttpResponse.code.to_i >= 200 && netHttpResponse.code.to_i < 300
      if success
        begin
          decoded = netHttpResponse.body.bdecode
        rescue
          error = "Tracker netHttpResponse body was not a valid bencoded string"
          success = false
          return self
        end

        if decoded.has_key? 'peers'
          peers = decodePeers(decoded['peers'])
        else
          error = "Tracker netHttpResponse didn't contain a peers property"
          success = false
        end

        if decoded.has_key? 'interval'
          interval = decoded['interval'].to_i
        end
      else
        error = netHttpResponse.body
      end
      
      result = TrackerResponse.new(success, error, peers)
      result.interval = interval if interval
      result
    end
  end
end
