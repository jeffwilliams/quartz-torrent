require 'quartz_torrent/bitfield.rb'
require 'bencode'
module QuartzTorrent

  # Represents a bittorrent peer protocol generic request message (not the specific piece request message).
  class PeerRequest
  end

  # Represents a bittorrent peer protocol handshake message.
  class PeerHandshake
    ProtocolName = "BitTorrent protocol"
    InfoHashLen = 20
    PeerIdLen = 20

    def initialize
      @infoHash = nil
      @peerId = nil
      @reserved = nil
    end

    def peerId=(v)
      raise "PeerId is not #{PeerIdLen} bytes long" if v.length != PeerIdLen
      @peerId = v
    end

    def infoHash=(v)
      raise "InfoHash is not #{InfoHashLen} bytes long" if v.length != InfoHashLen
      @infoHash = v
    end

    attr_accessor :peerId
    attr_accessor :infoHash
    attr_accessor :reserved

    # Serialize this PeerHandshake message to the passed io object. Throws exceptions on failure.
    def serializeTo(io)
      raise "PeerId is not set" if ! @peerId
      raise "InfoHash is not set" if ! @infoHash
      result = [ProtocolName.length].pack("C")
      result << ProtocolName
      result << [0,0,0,0,0,0x10,0,0].pack("C8") # Reserved. 0x10 means we support extensions (BEP 10).
      result << @infoHash
      result << @peerId
      
      io.write result
    end

    # Unserialize a PeerHandshake message from the passed io object and 
    # return it. Throws exceptions on failure.
    def self.unserializeFrom(io)
      result = PeerHandshake.new
      len = io.read(1).unpack("C")[0]
      proto = io.read(len)
      raise "Unrecognized peer protocol name '#{proto}'" if proto != ProtocolName
      result.reserved = io.read(8) # reserved
      result.infoHash = io.read(InfoHashLen)
      result.peerId = io.read(PeerIdLen)
      result
    end

    # Unserialize the first part of a PeerHandshake message from the passed io object
    # up to but not including the peer id. This is needed when handling a handshake from
    # the tracker which doesn't have a peer id.
    def self.unserializeExceptPeerIdFrom(io)
      result = PeerHandshake.new
      len = io.read(1).unpack("C")[0]
      proto = io.read(len)
      raise "Unrecognized peer protocol name '#{proto}'" if proto != ProtocolName
      result.reserved = io.read(8) # reserved
      result.infoHash = io.read(InfoHashLen)
      result
    end
  end

  # Represents a bittorrent peer protocol wire message (a non-handshake message).
  # All messages other than handshake have a 4-byte length, 1-byte message id, and payload.
  class PeerWireMessage
    MessageKeepAlive = -1
    MessageChoke = 0
    MessageUnchoke = 1
    MessageInterested = 2
    MessageUninterested = 3
    MessageHave = 4
    MessageBitfield = 5
    MessageRequest = 6
    MessagePiece = 7
    MessageCancel = 8
    MessageExtended = 20

    def initialize(messageId)
      @messageId = messageId
    end

    attr_reader :messageId

    def serializeTo(io)
      io.write [payloadLength+1].pack("N")
      io.write [@messageId].pack("C")
    end
  
    # Subclasses must implement this method. It should return an integer.
    def payloadLength
      raise "Subclasses of PeerWireMessage must implement payloadLength but #{self.class} didn't"
    end

    # Total message length
    def length
      payloadLength + 5
    end

    def unserialize(payload)
      raise "Subclasses of PeerWireMessage must implement unserialize but #{self.class} didn't"
    end

    def to_s
      "#{self.class} message"
    end
  end

  # KeepAlive message. Sent periodically to ensure peer is available.
  class KeepAlive < PeerWireMessage
    def initialize
      super(MessageKeepAlive)
    end

    def length
      4
    end

    def serializeTo(io)
      # A KeepAlive is just a 4byte length set to 0.
      io.write [0].pack("N")
    end

    def unserialize(payload)
    end
  end

  # Choke message. Sent to tell peer they are choked.
  class Choke < PeerWireMessage
    def initialize
      super(MessageChoke)
    end

    def payloadLength
      0
    end

    def unserialize(payload)
    end
  end
  
  # Unchoke message. Sent to tell peer they are unchoked.
  class Unchoke < PeerWireMessage
    def initialize
      super(MessageUnchoke)
    end
    def payloadLength
      0
    end
    def unserialize(payload)
    end
  end

  # Interested message. Sent to tell peer we are interested in some piece they have.
  class Interested < PeerWireMessage
    def initialize
      super(MessageInterested)
    end
    def payloadLength
      0
    end
    def unserialize(payload)
    end
  end

  # Uninterested message. Sent to tell peer we are not interested in any piece they have.
  class Uninterested < PeerWireMessage
    def initialize
      super(MessageUninterested)
    end
    def payloadLength
      0
    end
    def unserialize(payload)
    end
  end

  # Have message. Sent to all connected peers to notify that we have completed downloading the specified piece.
  class Have < PeerWireMessage
    def initialize
      super(MessageHave)
    end

    attr_accessor :pieceIndex
  
    def payloadLength
      4
    end

    def serializeTo(io)
      super(io)
      io.write [@pieceIndex].pack("N")
    end

    def unserialize(payload)
      @pieceIndex = payload.unpack("N")[0]
    end

    def to_s
      s = super
      s + ": piece index=#{@pieceIndex}"
    end
  end

  # Bitfield message. Sent on initial handshake to notify peer of what pieces we have.
  class BitfieldMessage < PeerWireMessage
    def initialize
      super(MessageBitfield)
    end

    attr_accessor :bitfield
  
    def payloadLength
      bitfield.byteLength
    end

    def serializeTo(io)
      super(io)
      io.write @bitfield.serialize
    end

    def unserialize(payload)
      @bitfield = Bitfield.new(payload.length*8) if ! @bitfield
      @bitfield.unserialize(payload)
    end
  end
  
  # Request message. Request a block within a piece.
  class Request < PeerWireMessage
    def initialize
      super(MessageRequest)
    end

    attr_accessor :pieceIndex
    attr_accessor :blockOffset
    attr_accessor :blockLength

    def payloadLength
      12
    end

    def serializeTo(io)
      super(io)
      io.write [@pieceIndex, @blockOffset, @blockLength].pack("NNN")
    end

    def unserialize(payload)
      @pieceIndex, @blockOffset, @blockLength = payload.unpack("NNN")
    end

    def to_s
      s = super
      s + ": piece index=#{@pieceIndex}, block offset=#{@blockOffset}, block length=#{@blockLength}"
    end
  end
 
  # Piece message. Response to a Request message containing the block of data within a piece.
  class Piece < PeerWireMessage
    def initialize
      super(MessagePiece)
    end

    attr_accessor :pieceIndex
    attr_accessor :blockOffset
    attr_accessor :data

    def payloadLength
      8 + @data.length     
    end

    def serializeTo(io)
      super(io)
      io.write [@pieceIndex, @blockOffset, @data].pack("NNa*")
    end

    def unserialize(payload)
      @pieceIndex, @blockOffset, @data = payload.unpack("NNa*")
    end

    def to_s
      s = super
      s + ": piece index=#{@pieceIndex}, block offset=#{@blockOffset}"
    end
  end
 
  # Cancel message. Cancel an outstanding request.
  class Cancel < PeerWireMessage
    def initialize
      super(MessageCancel)
    end

    attr_accessor :pieceIndex
    attr_accessor :blockOffset
    attr_accessor :blockLength

    def payloadLength
      12
    end

    def serializeTo(io)
      super(io)
      io.write [@pieceIndex, @blockOffset, @blockLength].pack("NNN")
    end

    def unserialize(payload)
      @pieceIndex, @blockOffset, @blockLength = payload.unpack("NNN")
    end

    def to_s
      s = super
      s + ": piece index=#{@pieceIndex}, block offset=#{@blockOffset}, block length=#{@blockLength}"
    end
  end

  # Extended message. These are extra messages not defined in the base protocol.
  class Extended < PeerWireMessage
    def initialize
      super(MessageExtended)
    end

    attr_accessor :extendedMessageId

    def payloadLength
      1 + extendedMsgPayloadLength
    end

    def unserialize(payload)
      @extendedMessageId = payload.unpack("C")
    end

    def serializeTo(io)
      super(io)
      io.write [@extendedMessageId].pack("C")
    end

    def to_s
      s = super
      s + ": extendedMessageId=#{@extendedMessageId}"
    end

    protected
    def extendedMsgPayloadLength
      raise "Subclasses of Extended must implement extendedMsgPayloadLength"
    end

    private
    # Given an extended message id, return the subclass of Extended for that message.
    # peerExtendedMessageList should be an array indexed by extended message id that returns a subclass of Extended
    def self.classForMessage(id, peerExtendedMessageList)
      return ExtendedHandshake if id == 0
 
      raise "Unknown extended peer message id #{id}" if id > peerExtendedMessageList
      peerExtendedMessageMap[id]
    end
  end

  # An Extended Handshake message. Used to negotiate supported extensions.
  class ExtendedHandshake < Extended
    def initialize
      super()
      @dict = {}
      @extendedMessageId = 0
    end

    attr_accessor :dict

    def unserialize(payload)
      super(payload)
      payload = payload[1,payload.length]
      begin
        @dict = payload.bdecode
      rescue
        e = RuntimeError.new("Error bdecoding payload '#{payload}' (payload length = #{payload.length})")
        e.set_backtrace($!.backtrace)
        raise e
      end
    end

    def serializeTo(io)
      super(io)
      io.write dict.bencode
    end

    private
    def extendedMsgPayloadLength
      dict.bencode.length
    end
  end

  # An Extended Metainfo message. Used to request metadata pieces, or provide responses to those requests.
  class ExtendedMetaInfo < Extended
    def initialize
      super()
      @extendedMessageId = 0
      @msgType = nil
      @piece = nil
      @totalSize = nil
      @data = nil
      @dict = {}
    end

    attr_accessor :dict
    # Message type as a symbol. One of :request, :data, or :reject
    attr_accessor :msgType
    attr_accessor :piece
    # This field is only set if the msgType is :piece 
    attr_accessor :totalSize
    # This field is only set if the msgType is :piece. It contains the data for the piece.
    attr_accessor :data

    def unserialize(payload)
      # Unserialize extended message id
      super(payload)

      # Rest of the message is a bencoded dictionary.
      # Piece messages of this class are encoded in an interesting way: the bencoded dictionary
      # is concatenated with the arbitrary binary data of the piece at the end. To decode this
      # we need to know the position of when we've finished reading the dictionary. We do this by
      # using a Parser object from the bencode library which maintains a stream object which happens
      # to know the current offset of the parsing.

      payload = payload[1,payload.length]
      parser = BEncode::Parser.new payload

      begin
        @dict = parser.parse!
      rescue
        e = RuntimeError.new("Error bdecoding payload '#{payload}' (payload length = #{payload.length})")
        e.set_backtrace($!.backtrace)
        raise e
      end

      @msgType = @dict['msg_type']
      raise "Extended Metainfo message contained no 'msg_type' key." if ! @msgType
      if @msgType == 0
        @msgType = :request
      elsif @msgType == 1
        @msgType = :piece
      elsif @msgType == 2
        @msgType = :reject
      else
        raise "Unknown message type '#{@msgType}' in Extended Metainfo message"
      end

      @piece = @dict['piece']
      raise "Extended Metainfo message contained no 'piece' key." if ! @piece
      
      @totalSize = @dict['total_size'] if @msgType == :piece

      # If this is a piece message, read the data after the dictionary.
      @data = parser.stream.read if @msgType == :piece
  
    end

    def serializeTo(io)
      super(io)
      updateDictFromProps
      io.write @dict.bencode
      raise "Extended metainfo piece messages must have piece data. This one's data was nil" if ! @data && dict['msg_type'] == 1
      io.write @data if dict['msg_type'] == 1
    end

    private
    def extendedMsgPayloadLength
      updateDictFromProps
      len = @dict.bencode.length
      len += @data.length if dict['msg_type'] == 1
      len
    end

    def updateDictFromProps
      @dict['msg_type'] = msgTypeSymToVal(@msgType) if ! @dict.has_key?('msg_type') && @msgType
      @dict['piece'] = @piece if ! @dict.has_key?('piece') 
      @dict['total_size'] = @data.length if @data
    end

    def msgTypeSymToVal(sym)
      if sym == :request
        0
      elsif sym == :piece
        1
      elsif sym == :reject
        2
      else
        raise "Unknown msg type #{sym}"
      end
    end
  end

end

