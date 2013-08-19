require 'quartz_torrent/peermsg'
module QuartzTorrent
  # This class contains constants that represent our numbering of the Bittorrent extensions we support.
  # It also has some utility methods related to extensions.
  class Extension
  
    MetadataExtensionId = 1

    # Parameter info should be the metadata info struct. It is used to determine the size to send 
    # when negotiating the metadata extension.
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

    def self.peerMsgClassForExtensionName(info)
      if info == 'ut_metadata'
        ExtendedMetaInfo
      else
        nil
      end
    end
  end
end
