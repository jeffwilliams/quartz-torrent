require 'quartz_torrent/log'
require 'bencode'
require 'digest/sha1'

module QuartzTorrent
  
  # Torrent metainfo structure. This is what's usually found in .torrent files. This class
  # generally follows the structure of the metadata format.
  class Metainfo

    # If 'v' is null, throw an exception. Otherwise return 'v'.
    def self.valueOrException(v, msg)
      if ! v
        LogManager.getLogger("metainfo").error msg
        raise "Invalid torrent metainfo"
      end
      v
    end

    # Information about a file contained in the torrent.
    class FileInfo
      def initialize(length = nil, path = nil)
        @length = length
        @path = path
      end

      # Relative path to the file. For a single-file torrent this is simply the name of the file. For a multi-file torrent,
      # this is the directory names from the torrent and the filename separated by the file separator.
      attr_accessor :path
      # Length of the file.
      attr_accessor :length
  
      # Create a FileInfo object from a bdecoded structure.
      def self.createFromBdecode(bdecode)
        result = FileInfo.new
        result.length = Metainfo.valueOrException(bdecode['length'], "Torrent metainfo listed multiple files, and one is missing the length property.")
        path = Metainfo.valueOrException(bdecode['path'], "Torrent metainfo listed multiple files, and one is missing the path property.")

        result.path = ""
        path.each do |part|
          result.path << File::SEPARATOR if result.path.length > 0
          result.path << part
        end
  
        result
      end
    end

    # The 'info' property of the torrent metainfo.
    class Info
      def initialize
        @pieceLen = nil
        @pieces = nil
        @private = nil
        # Suggested file or directory name
        @name = nil
        # List of file info for files in the torrent. These include the directory name if this is a
        # multi-file download. For a single-file download the 
        @files = []
        @logger = LogManager.getLogger("metainfo")
      end

      # Array of FileInfo objects
      attr_accessor :files
      # Suggested file or directory name
      attr_accessor :name
      # Length of each piece in bytes. The last piece may be shorter than this.
      attr_accessor :pieceLen
      # Array of SHA1 digests of all peices. These digests are in binary format. 
      attr_accessor :pieces
      # True if no external peer source is allowed.
      attr_accessor :private

      # Total length of the torrent data in bytes.
      def dataLength
        files.reduce(0){ |memo,f| memo + f.length}
      end

      # Create a FileInfo object from a bdecoded structure.
      def self.createFromBdecode(bdecode)
        infoDict = bdecode['info']
        result = Info.new
        result.pieceLen = infoDict['piece length']
        result.private = infoDict['private']
        result.pieces = parsePieces(Metainfo.valueOrException(infoDict['pieces'], "Torrent metainfo is missing the pieces property."))
        result.name = Metainfo.valueOrException(infoDict['name'], "Torrent metainfo is missing the name property.")

        if infoDict.has_key? 'files'
          # This is a multi-file torrent
          infoDict['files'].each do |file|
            result.files.push FileInfo.createFromBdecode(file)
            result.files.last.path = result.name + File::SEPARATOR + result.files.last.path
          end
        else
          # This is a single-file torrent
          length = Metainfo.valueOrException(infoDict['length'], "Torrent metainfo listed a single file, but it is missing the length property.")
          result.files.push FileInfo.new(length, result.name)
        end

        result
      end

      # BEncode this info and return the result.
      def bencode
        hash = {}
    
        raise "Cannot encode Info object with nil pieceLen" if ! @pieceLen
        raise "Cannot encode Info object with nil name" if ! @name
        raise "Cannot encode Info object with nil pieces" if ! @pieces
        raise "Cannot encode Info object with nil files or empty files" if ! @files || @files.empty?

        hash['piece length'] = @pieceLen
        hash['private'] = @private if @private
        hash['name'] = @name
        hash['pieces'] = @pieces.join

        if @files.length > 1
          hash['files'] = @files.collect{ |file| {'length' => file.length, 'path' => file.path.split(File::SEPARATOR) }  }
        else
          hash['length'] = @files.first.length
        end
        hash.bencode
      end

      private
      # Parse the pieces of the torrent out of the metainfo.
      def self.parsePieces(p)
        # Break into 20-byte portions.
        if p.length % 20 != 0
          @logger.error "Torrent metainfo contained a pieces property that was not a multiple of 20 bytes long."
          raise "Invalid torrent metainfo"
        end

        result = []
        index = 0
        while index < p.length
          result.push p[index,20].unpack("a20")[0]
          index += 20
        end
        result
      end
    end

    def initialize
      @info = nil
      @announce = nil
      @announceList = nil
      @creationDate = nil
      @comment = nil
      @createdBy = nil
      @encoding = nil
    end

    # A Metainfo::Info object
    attr_accessor :info

    # A 20-byte SHA1 hash of the value of the info key from the metainfo. This is neede when connecting
    # to the tracker or to a peer.
    attr_accessor :infoHash

    # Announce URL of the tracker
    attr_accessor :announce
    attr_accessor :announceList

    # Creation date as a ruby Time object
    attr_accessor :creationDate
    # Comment
    attr_accessor :comment
    # Created By
    attr_accessor :createdBy
    # The string encoding format used to generate the pieces part of the info dictionary in the .torrent metafile
    attr_accessor :encoding

    # Create a Metainfo object from the passed bencoded string.
    def self.createFromString(data)
      logger = LogManager.getLogger("metainfo")

      decoded = data.bdecode
      logger.debug "Decoded torrent metainfo: #{decoded.inspect}"
      result = Metainfo.new
      result.createdBy = decoded['created by']
      result.comment = decoded['comment']
      result.creationDate = decoded['creation date']
      if result.creationDate 
        if !result.creationDate.is_a?(Integer)
          if result.creationDate =~ /^\d+$/
            result.creationDate = result.creationDate.to_i
          else
            logger.warn "Torrent metainfo contained invalid date: '#{result.creationDate.class}'"
            result.creationDate = nil
          end
        end

        result.creationDate = Time.at(result.creationDate) if result.creationDate
      end
      result.encoding = decoded['encoding']
      result.announce = decoded['announce'].strip
      result.announceList = decoded['announce-list']
      result.info = Info.createFromBdecode(decoded)
      result.infoHash = Digest::SHA1.digest( decoded['info'].bencode )
    
      result
    end

    # Create a Metainfo object from the passed IO.
    def self.createFromIO(io)
      self.createFromString(io.read)
    end

    # Create a Metainfo object from the named file.
    def self.createFromFile(path)
      result = 
      File.open(path,"r") do |io|
        result = self.createFromIO(io)
      end
      result
    end
  end
end
