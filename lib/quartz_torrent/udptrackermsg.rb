module QuartzTorrent
  class UdpTrackerMessage
    ActionConnect = 0
    ActionAnnounce = 1
    ActionScrape = 2
    ActionError = 3

    EventNone = 0
    EventCompleted = 1
    EventStarted = 2
    EventStopped = 3

    # Pack the number 'num' as a network byte order signed integer, 'len' bytes long. 
    # Negative numbers are written in two's-compliment notation.
    def self.packAsNetworkOrder(num, len)
      result = ""
      len.times do
        result << (num & 0xff)
        num >>= 8
      end
      result.reverse
    end

    # Unpack the number stored in 'str' assuming it is a network byte order signed integer. 
    # Negative numbers are assumed to be in two's-compliment notation.
    def self.unpackNetworkOrder(str, len = nil)
      result = 0
      first = true
      negative = false
      index = 0
      str.each_byte do |b|
        if first
          negative = (b & 0x80) > 0
          first = false
        end
        result <<= 8
        result += b
        index += 1
        break if len && index == len
      end
      if negative
        # Internally the value is being represented unsigned. To make it signed,
        # we first take the ones compliment of the value, remove the sign bit, and add one.
        # This takes the two's compliment of the two's compliment of the number, which results
        # in the absolute value of the original number. Finally we use the unary - operator to
        # make the value negative.
        result = -(((~result) & 0x7fffffffffffffff) + 1)
      end
      result 
    end
  end

  # Superclass for UDP tracker requests.
  class UdpTrackerRequest
    def initialize
      @connectionId = 0x41727101980
      @action = UdpTrackerMessage::ActionConnect
      # Get a number that is a valid 32-bit signed integer.
      @transactionId = rand(0x10000000)-8000000
    end

    # Get the connectionId as an integer
    attr_reader :connectionId
    # Get the action as an integer. Should be one of the UdpTrackerMessage::Action* constants
    attr_reader :action
    # Get the transactionId as an integer. 
    attr_reader :transactionId

    # Set the connectionId. Value must be an integer
    def connectionId=(v)
      raise "The 'connectionId' field must be an integer" if ! v.is_a?(Integer)
      @connectionId = v
    end
    # Set the action. Value should be one of the UdpTrackerMessage::Action* constants
    def action=(v)
      raise "The 'action' field must be an integer" if ! v.is_a?(Integer)
      @action = v
    end
    # Set the transactionId. Value must be an integer. If not set a random number is used as per the specification.
    def transactionId=(v)
      raise "The 'transactionId' field must be an integer" if ! v.is_a?(Integer)
      @transactionId = v
    end
  end

  # Superclass for UDP tracker responses
  class UdpTrackerResponse
    def initialize
      @connectionId = nil
      @action = nil
      @transactionId = nil
    end
  
    # ConnectionId as an integer
    attr_accessor :connectionId
    # Get the action as an integer. Should be one of the UdpTrackerMessage::Action* constants
    attr_accessor :action
    # Get the transactionId as an integer
    attr_accessor :transactionId
  end

  class UdpTrackerConnectRequest < UdpTrackerRequest
    def serialize
      result = UdpTrackerMessage::packAsNetworkOrder(@connectionId, 8)
      result << UdpTrackerMessage::packAsNetworkOrder(@action, 4)
      result << UdpTrackerMessage::packAsNetworkOrder(@transactionId, 4)
      result
    end
  end

  class UdpTrackerConnectResponse < UdpTrackerResponse
    def initialize
      super
    end

    def self.unserialize(msg)
      raise "Invalid connect response: it is #{msg.length} when it must be at least 16" if msg.length < 16
      result = UdpTrackerConnectResponse.new
      result.action = UdpTrackerMessage::unpackNetworkOrder(msg,4)
      result.transactionId = UdpTrackerMessage::unpackNetworkOrder(msg[4,4],4)
      result.connectionId = UdpTrackerMessage::unpackNetworkOrder(msg[8,8],8)
      raise "Invalid connect response: action is not connect" if result.action != UdpTrackerMessage::ActionConnect
      result
    end

    def self.tohex(str)  
      result = ""
      str.each_byte do |b|
        result << b.to_s(16)
      end
      result
    end
  end

  class UdpTrackerAnnounceRequest < UdpTrackerRequest
    def initialize(connectionId)
      super()
      @connectionId = connectionId
      @action = UdpTrackerMessage::ActionAnnounce
      @infoHash = nil
      @peerId = nil
      @downloaded = nil
      @left = nil
      @uploaded = nil
      @event = nil
      # 0 means allow tracker to assume the sender's IP address is the one it's looking for
      # http://www.rasterbar.com/products/libtorrent/udp_tracker_protocol.html
      @ipAddress = 0
      @key = rand(0xffffffff)
      # Number of peers requested: default.
      @numWant = -1
      @port = nil
    end

    attr_accessor :infoHash
    attr_accessor :peerId
    attr_reader   :downloaded
    attr_reader   :left
    attr_reader   :uploaded
    attr_reader   :event
    attr_accessor :ipAddress
    attr_accessor :key
    attr_accessor :numWant
    attr_accessor :port

    def downloaded=(v)
      raise "The 'downloaded' field must be an integer" if ! v.is_a?(Integer)
      @downloaded = v
    end

    def left=(v)
      raise "The 'left' field must be an integer" if ! v.is_a?(Integer)
      @left = v
    end

    def uploaded=(v)
      raise "The 'uploaded' field must be an integer" if ! v.is_a?(Integer)
      @uploaded = v
    end

    def event=(v)
      raise "The 'event' field must be an integer" if ! v.is_a?(Integer)
      @event = v
    end

    def numWant=(v)
      raise "The 'numWant' field must be an integer" if ! v.is_a?(Integer)
      @numWant = v
    end

    def port=(v)
      raise "The 'port' field must be an integer" if ! v.is_a?(Integer)
      @port = v
    end

    def serialize
      result = UdpTrackerMessage::packAsNetworkOrder(@connectionId, 8)
      result << UdpTrackerMessage::packAsNetworkOrder(@action, 4)
      result << UdpTrackerMessage::packAsNetworkOrder(@transactionId, 4)
      result << infoHash
      result << peerId
      result << UdpTrackerMessage::packAsNetworkOrder(@downloaded, 8)
      result << UdpTrackerMessage::packAsNetworkOrder(@left, 8)
      result << UdpTrackerMessage::packAsNetworkOrder(@uploaded, 8)
      result << UdpTrackerMessage::packAsNetworkOrder(@event, 4)
      result << UdpTrackerMessage::packAsNetworkOrder(@ipAddress, 4)
      result << UdpTrackerMessage::packAsNetworkOrder(@key, 4)
      result << UdpTrackerMessage::packAsNetworkOrder(@numWant, 4)
      result << UdpTrackerMessage::packAsNetworkOrder(@port, 2)
      result
    end
  end

  class UdpTrackerAnnounceResponse < UdpTrackerResponse
    def initialize
      super
      @interval = nil     
      @leechers = nil     
      @seeders = nil     
      @ips = []
      @ports = []
    end

    attr_accessor :interval
    attr_accessor :leechers
    attr_accessor :seeders
    attr_accessor :ips
    attr_accessor :ports

    def self.unserialize(msg)
      raise "Invalid connect response: it is #{msg.length} when it must be at least 20" if msg.length < 20
      result = UdpTrackerAnnounceResponse.new
      result.action = UdpTrackerMessage::unpackNetworkOrder(msg,4)
      result.transactionId = UdpTrackerMessage::unpackNetworkOrder(msg[4,4],4)
      result.interval = UdpTrackerMessage::unpackNetworkOrder(msg[8,4],4)
      result.leechers = UdpTrackerMessage::unpackNetworkOrder(msg[12,4],4)
      result.seeders = UdpTrackerMessage::unpackNetworkOrder(msg[16,4],4)
      
      index = 20
      while index+6 < msg.length
        result.ips.push msg[index,4]
        result.ports.push msg[index+4,2]
        index += 6
      end
      result
    end
  end
  
  
end
