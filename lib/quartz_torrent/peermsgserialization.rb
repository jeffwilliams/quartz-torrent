require 'bencode'
require 'quartz_torrent/peermsg'
require 'quartz_torrent/extension'

module QuartzTorrent
  class PeerWireMessageSerializer
    @@classForMessage = nil
    # The mapping of our extended message ids to extensions. This is different than @extendedMessageIdToClass which is 
    # the mapping of peer message ids to extensions, which is different for every peer.
    @@classForExtendedMessage = nil

    def initialize
      # extendedMessageIdToClass is the mapping of extended message ids that the peer has sent to extensions.
      @extendedMessageIdToClass = [ExtendedHandshake]
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
        extendedMsgId = @extendedMessageIdToClass.index msg.class
        raise "Unsupported extended peer message #{msg.class}" if ! extendedMsgId
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

      if @@classForExtendedMessage.nil?
        @@classForExtendedMessage = []
        @@classForExtendedMessage[Extension::MetadataExtensionId] = ExtendedMetaInfo
      end
      
      result = @@classForMessage[id]
      
      if result == Extended && payload
        # Extended messages have further subtypes.
        extendedMsgId = payload.unpack("C")[0]
        if extendedMsgId == 0
          result = ExtendedHandshake
        else
          # In this case the extended message number is the one we told our peers to use, not the one the peer told us.
          result = @@classForExtendedMessage[extendedMsgId]
          raise "Unsupported extended peer message id '#{extendedMsgId}'" if ! result 
        end

      end

      result
    end
  
    def updateExtendedMessageIdsFromHandshake(msg)
      if msg.is_a?(ExtendedHandshake)
        if msg.dict && msg.dict["m"]
          msg.dict["m"].each do |extName, extId|
            # Update the list here.
            clazz = Extension.peerMsgClassForExtensionName(extName)
            if clazz  
              @logger.debug "Peer supports extension #{extName} using id '#{extId}'."
              @extendedMessageIdToClass[extId] = clazz
            else
              @logger.warn "Peer supports extension #{extName} using id '#{extId}', but I don't know what class to use for that extension."
            end
          end
        else
          @logger.warn "Peer sent extended handshake without the 'm' key."
        end
      end
    end

  end
end
