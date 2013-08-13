require 'bencode'
require 'quartz_torrent/peermsg.rb'

module QuartzTorrent
  class PeerWireMessageSerializer
    @@classForMessage = nil

    def initialize
      extendedMessageIdToClass = [ExtendedHandshake]
      @logger = LogManager.getLogger("peermsg_serializer")
    end

    def unserializeFrom(io)
      packedLength = io.read(4)
      raise EOFError.new if packedLength.length == 0

      length = packedLength.unpack("N")[0]
      raise "Received peer message with length #{length}. All messages must have length >= 0" if length < 0
      return KeepAlive.new if length == 0
      
      id = io.read(1).unpack("C")[0]
      payload = io.read(length-1)

      #raise "Unsupported peer message id #{id}" if id >= self.classForMessage.length
      clazz = classForMessage(id, payload)
      raise "Unsupported peer message id #{id}" if ! clazz

      result = clazz.new
      result.unserialize(payload)
      updateExtendedMessageIdsFromHandshake(result)
      result
    end

    def serializeTo(msg, io)
      if msg.is_a?(Extended)
        # Set the extended message id
        extendedMsgId = extendedMessageIdToClass.index msg.class
        raise "Unsupported extended peer message id #{extendedMsgId}" if ! extendedMsgId
        msg.extendedMessageId = extendedMsgId
      end
      msg.serializeTo(io)
    end

    private
    # Determine the class associated with the message type passed.
    def classForMessage(id, payload)
      if @@classForMessage.nil?
        @@classForMessage = [Choke, Unchoke, Interested, Uninterested, Have, BitfieldMessage, Request, Piece, Cancel]
        @@classForMessage[20] = Extended
      end
      
      result = @@classForMessage[id]
      
      if result == Extended && payload
        # Extended messages have further subtypes.
        extendedMsgId = payload.unpack("C")[0]
        if extendedMsgId == 0
          result = ExtendedHandshake
        else
          result = extendedMessageIdToClass[extendedMsgId]
          raise "Unsupported extended peer message id #{extendedMsgId}" if ! result 
        end

      end

      result
    end
  
    def updateExtendedMessageIdsFromHandshake(msg)
      if msg.is_a?(ExtendedHandshake)
        if msg.dict && msg.dict["m"]
          msg.dict["m"].each do |extName, extId|
            # Update the list here.
            @logger.debug "Peer supports extension #{extName}."
          end
        else
          @logger.warn "Peer sent extended handshake without the 'm' key."
        end
      end
    end

  end
end
