require 'quartz_torrent/peermsg'
module QuartzTorrent
  # This class contains constants that represent our numbering of the Bittorrent peer-protocol extensions we support.
  # It also has some utility methods related to extensions.
  class Extension
  
    # The metadata extension (BEP 9)
    MetadataExtensionId = 1

    # Create an ExtendedHandshake object based on the passed Torrent metadata info struct. 
    # @param info The torrent metadata info struct. It is used to determine the size to send 
    #             when negotiating the metadata extension.
    def self.createExtendedHandshake(info)
      msg = ExtendedHandshake.new
      
      extensionIds = {
        'ut_metadata' => MetadataExtensionId
      }

      msg.dict['m'] = extensionIds

      if info
        msg.dict['metadata_size'] = info.bencode.length
      else
        msg.dict['metadata_size'] = 0
      end

      msg
    end

    # Get the class to use to serialize and unserialize the specified Bittorent extension. Returns nil if we don't support that extension.
    # @param info The name of a bittorrent extension as specified in the BEP, for example 'ut_metadata'.
    def self.peerMsgClassForExtensionName(info)
      if info == 'ut_metadata'
        ExtendedMetaInfo
      else
        nil
      end
    end
  end
end
