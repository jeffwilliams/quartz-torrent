require 'quartz_torrent/util'
require 'uri'
module QuartzTorrent
  class MagnetURI
    # Create a new MagnetURI object given a magnet URI string.
    def initialize(str)
      @params = {}

      if str =~ /magnet:\?(.*)/
        parseQuery $1
      else
        raise "Not a magnet URI"
      end
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
            raise "Base32 encoding of magnet links is not supported"
          end
          break
        end
      end
      result
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
