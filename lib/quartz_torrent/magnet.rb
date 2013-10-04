require 'quartz_torrent/util'
require 'uri'
require 'base32'

module QuartzTorrent
  class MagnetURI
    @@regex = /magnet:\?(.*)/
  
    # Create a new MagnetURI object given a magnet URI string.
    def initialize(str)
      @params = {}
      @raw = str

      if str =~ @@regex
        parseQuery $1
      else
        raise "Not a magnet URI"
      end
    end

    attr_reader :raw

    def self.magnetURI?(str)
      str =~ @@regex
    end

    # Return the value of the specified key from the magnet URI.
    def [](key)
      @params[key]
    end

    # Return the first Bittorrent info hash found in the magnet URI. The returned
    # info hash is in binary format.
    def btInfoHash
      result = nil
      @params['xt'].each do |topic|
        if topic =~ /urn:btih:(.*)/
          hash = $1
          if hash.length == 40
            # Hex-encoded info hash. Convert to binary.
            result = [hash].pack "H*" 
          else
            # Base32 encoded
            result = Base32.decode hash
          end
          break
        end
      end
      result
    end

    # Return the first tracker URL found in the magnet link. Returns nil if the magnet has no tracker info.
    def tracker
      tr = @params['tr']
      if tr
        tr.first
      else
        nil
      end
    end

    # Return the first display name found in the magnet link. Returns nil if the magnet has no display name.
    def displayName
      dn = @params['dn']
      if dn
        dn.first
      else
        nil
      end
    end

    # Create a magnet URI string given the metainfo from a torrent file.
    def self.encodeFromMetainfo(metainfo)
      s = "magnet:?xt=urn:btih:"
      s << metainfo.infoHash.unpack("H*").first
      s << "&tr="
      s << metainfo.announce
    end

    private
    def parseQuery(query)
      query.split('&').each do |part|
        if part =~ /(.*)=(.*)/
          name = $1
          val = $2
          name = $1 if name =~ /(.*).\d+$/
          @params.pushToList name, URI.unescape(val).tr('+',' ')
        end
      end
    end
  end
end
