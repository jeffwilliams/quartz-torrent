require 'digest/sha1'
require 'fileutils'
require 'thread'
require 'quartz_torrent/regionmap'
require 'quartz_torrent/bitfield'
require 'quartz_torrent/util'
require 'quartz_torrent/semaphore'

module QuartzTorrent
  class RequestedBlock
    attr_accessor :index
    attr_accessor :time
  end

  # Represents a piece as it is being downloaded.
  class IncompletePiece
    # Which blocks have we downloaded of this piece
    attr_accessor :completeBlockBitfield

    # Which blocks have been requested. List of RequestedBlock objects.
    attr_accessor :requests

    # Piece index inside the torrent
    attr_accessor :index

    # Do we have all pieces?     
    def complete?
    end
  end

  # Represents a unique region of a file: a filename, offset, and length.
  class FileRegion
    def initialize(path = nil, offset = nil, length = nil)
      @path = path
      @offset = offset
      @length = length
    end
  
    attr_accessor :path
    attr_accessor :offset
    attr_accessor :length
  end

  # Maps pieces to sections of files. 
  class PieceMapper
    # Create a new PieceMapper that will map to files inside 'baseDirectory'. Parameter 'torrinfo' should
    # be a Metainfo::Info object (the info part of the metainfo).
    def initialize(baseDirectory, torrinfo)
      @torrinfo = torrinfo
      @pieceSize = torrinfo.pieceLen
      @logger = LogManager.getLogger("piecemapper")

      @fileRegionMap = RegionMap.new
      offset = 0
      @logger.debug "Map (offset to path):"
      torrinfo.files.each do |file|
        offset += file.length
        path = baseDirectory + File::SEPARATOR + file.path
        @fileRegionMap.add offset-1, path
        @logger.debug "  #{offset-1}\t#{path}"
      end      
    end

    # Return a list of FileRegion objects. The FileRegion offsets specify
    # in order which regions of files the piece covers.
    def findPiece(pieceIndex)
      leftOffset = @pieceSize*pieceIndex
      rightOffset = leftOffset + @pieceSize-1

      findPart(leftOffset, rightOffset)
    end

    # Return a list of FileRegion objects. The FileRegion offsets specify
    # in order which regions of files the piece covers.
    def findBlock(pieceIndex, offset, length)
      leftOffset = @pieceSize*pieceIndex + offset
      rightOffset = leftOffset + length-1

      findPart(leftOffset, rightOffset)
    end

    private
    def findPart(leftOffset, rightOffset)
      # [index, value, left, right, offset] 
      leftData = @fileRegionMap.find(leftOffset)
      rightData = @fileRegionMap.find(rightOffset)
      if rightData.nil?
        # Right end is past the end of the rightmost limit. Scale it back.
        rightData = @fileRegionMap.last
        rightData.push rightData[3]-rightData[2]
      end
      raise "Offset #{leftOffset} is out of range" if leftData.nil?
      leftIndex = leftData[0]
      rightIndex = rightData[0]
      if leftIndex == rightIndex
        return [FileRegion.new(leftData[1], leftData[4], rightData[4]-leftData[4]+1)]
      end

      result = []
      (leftIndex..rightIndex).each do |i|
        if i == leftIndex 
          result.push FileRegion.new(leftData[1], leftData[4], leftData[3]-leftData[4]-leftData[2]+1)
        elsif i == rightIndex    
          result.push FileRegion.new(rightData[1], 0, rightData[4]+1)
        else
          value, left, right = @fileRegionMap[i]
          result.push FileRegion.new(value, 0, right-left+1)
        end
      end
      result
    end
  end

  # Basic IOManager that isn't used by a reactor.
  class IOManager
    def initialize
      @io = {}
    end

    def get(path)
      @io[path]
    end

    def open(path)
      # Open the file for read/write.
      # If the file exists, open as r+ so it is not truncated.
      # Otherwise open as w+
      if File.exists?(path)
        io = File.open(path, "rb+")
      else
        io = File.open(path, "wb+")
      end
      @io[path] = io
      io
    end

    def flush
      @io.each do |k,v|
        v.flush
      end
    end
  end

  # Can read and write pieces and blocks of a torrent.
  class PieceIO
    # Create a new PieceIO that will map to files inside 'baseDirectory'. Parameter 'torrinfo' should
    # be a Metainfo::Info object (the info part of the metainfo).
    def initialize(baseDirectory, torrinfo, ioManager = IOManager.new)
      @baseDirectory = baseDirectory
      @torrinfo = torrinfo
      @pieceMapper = PieceMapper.new(baseDirectory, torrinfo)
      @ioManager = ioManager
      @logger = LogManager.getLogger("pieceio")
      @torrentDataLength = torrinfo.dataLength
    end

    # Get the overall length of the torrent data
    attr_reader :torrentDataLength

    # Write a block to an in-progress piece. The block is written to 
    # piece 'peiceIndex', at offset 'offset'. The block data is in block. 
    # Throws exceptions on failure.
    def writeBlock(pieceIndex, offset, block)
      regions = @pieceMapper.findBlock(pieceIndex, offset, block.length)
      indexInBlock = 0
      regions.each do |region|
        # Get the IO for the file with path 'path'. If we are being used in a reactor, this is the IO facade. If we
        # are not then this is a real IO.
        io = @ioManager.get(region.path)
        if ! io
          # No IO for this file. 
          raise "This process doesn't have write permission for the file #{region.path}" if File.exists?(region.path) && ! File.writable?(region.path)

          # Ensure parent directories exist.
          dir = File.dirname region.path
          FileUtils.mkdir_p dir if ! File.directory?(dir)

          begin
            io = @ioManager.open(region.path)
          rescue
            @logger.error "Opening file #{region.path} failed: #{$!}"
            raise "Opening file #{region.path} failed"
          end
        end

        io.seek region.offset, IO::SEEK_SET
        begin
          io.write(block[indexInBlock, region.length])
          indexInBlock += region.length
        rescue
          # Error when writing...
          @logger.error "Writing block to file #{region.path} failed: #{$!}"
          piece = nil
          break
        end

        break if indexInBlock >= block.length
      end
    end

    # Read a block from a completed piece. Returns nil if the block doesn't exist yet. Throws exceptions
    # on error (for example, opening a file failed)
    def readBlock(pieceIndex, offset, length)
      readRegions @pieceMapper.findBlock(pieceIndex, offset, length)
    end

    # Read a piece. Returns nil if the piece is not yet present.
    # NOTE: this method expects that if the ioManager is a reactor iomanager, 
    # that the io was set with errorHandler=false so that we get the EOF errors.
    def readPiece(pieceIndex)
      readRegions @pieceMapper.findPiece(pieceIndex)
    end
  
    def flush
      @ioManager.flush
    end

    private
    # Pass an ordered list of FileRegions to load.
    def readRegions(regions)
      piece = ""
      regions.each do |region|
        # Get the IO for the file with path 'path'. If we are being used in a reactor, this is the IO facade. If we
        # are not then this is a real IO.
        io = @ioManager.get(region.path)
        if ! io
          # No IO for this file. 
          if ! File.exists?(region.path)
            # This file hasn't been created yet by having blocks written to it.
            piece = nil
            break
          end

          raise "This process doesn't have read permission for the file #{region.path}" if ! File.readable?(region.path)

          begin
            io = @ioManager.open(region.path)
          rescue
            @logger.error "Opening file #{region.path} failed: #{$!}"
            raise "Opening file #{region.path} failed"
          end
        end
        io.seek region.offset, IO::SEEK_SET
        begin
          piece << io.read(region.length)
        rescue
          # Error when reading. Likely EOF, meaning this peice isn't all there yet.
          piece = nil
          break
        end
      end
      piece
    end
  end

  # A class that spawns a thread for performing PieceIO operations asynchronously.
  class PieceManager
    # The result of an asynchronous operation preformed by the PieceManager.
    class Result
      def initialize(requestId, success, data, error = nil)
        @success = success
        @error = error
        @data = data
        @requestId = requestId
      end

      # The ID of the request that this result is for. This is the same
      # as the id returned when making the request.
      attr_accessor :requestId
  
      # The error message if the operation was not successful
      attr_accessor :error

      # Any data returned in the result
      attr_accessor :data
  
      # Returns true if the operation was succesful
      def successful?
        @success
      end
    end

    # Create a new PieceManager that will map to files inside 'baseDirectory'. Parameter 'torrinfo' should
    # be a Metainfo::Info object (the info part of the metainfo).
    # Parameter 'alertCallback' should be a Proc. It will be called when an operation is complete. The 
    # alerted code can then retrieve the events from the completed queue.
    # This callback will be called from a different thread.
    def initialize(baseDirectory, torrinfo, alertCallback = nil)
      @alertCallback = alertCallback
      @mutex = Mutex.new
      @results = []
      @requests = []
      # The progress of requests as they are being serviced, keyed by request id.
      @requestProgress = {}
      @progressMutex = Mutex.new
      @requestsSemaphore = Semaphore.new
      @resultsSemaphore = Semaphore.new
      @baseDirectory = baseDirectory
      @torrinfo = torrinfo
      @pieceIO = PieceIO.new(baseDirectory, torrinfo)
      @requestId = 0
      @logger = LogManager.getLogger("piecemanager")
      @torrentDataLength = torrinfo.dataLength
      startThread
    end

    attr_reader :torrentDataLength
  
    # Read a block from the torrent asynchronously. When the operation
    # is complete the result is stored in the 'results' list.
    # This method returns an id that can be used to match the response 
    # to the request.
    # The readBlock and writeBlock methods are not threadsafe with respect to callers; 
    # they shouldn't be called by multiple threads concurrently.
    def readBlock(pieceIndex, offset, length)
      id = returnAndIncrRequestId
      @requests.push [id, :read_block, pieceIndex, offset, length]
      @requestsSemaphore.signal
      id
    end

    # Write a block to the torrent asynchronously. 
    def writeBlock(pieceIndex, offset, block)
      id = returnAndIncrRequestId
      @requests.push [id, :write_block, pieceIndex, offset, block]
      @requestsSemaphore.signal
      id
    end

    def readPiece(pieceIndex)
      id = returnAndIncrRequestId
      @requests.push [id, :read_piece, pieceIndex]
      @requestsSemaphore.signal
      id
    end

    # This is meant to be called when the torrent is first loaded
    # to check what pieces we've already downloaded.
    # The data property of the result for this call is set to a Bitfield representing
    # the complete pieces.
    def findExistingPieces
      id = returnAndIncrRequestId
      @requests.push [id, :find_existing]
      @requestsSemaphore.signal
      id
    end

    # Validate that the hash of the downloaded piece matches the hash from the metainfo.
    # The result is successful? if the hash matches, false otherwise. The data of the result is
    # set to the piece index.
    def checkPieceHash(pieceIndex)
      id = returnAndIncrRequestId
      @requests.push [id, :hash_piece, pieceIndex]
      @requestsSemaphore.signal
      id
    end

    # Flush to disk. The result for this operation is always successful.
    def flush()
      id = returnAndIncrRequestId
      @requests.push [id, :flush]
      @requestsSemaphore.signal
      id
    end

    # Result retrieval. Returns the next result, or nil if none are ready.
    # The results that are returned are PieceIOWorker::Result objects. 
    # For readBlock operations the data property of the result object contains
    # the block.
    def nextResult
      result = nil
      @mutex.synchronize do
        result = @results.shift
        @progressMutex.synchronize{ @requestProgress.delete result.requestId } if result
      end
      result
    end

    # Get the progress of the specified request as an integer between 0 and 100.
    # Currently, only the findExistingPieces operation registers progress; other operations
    # just return nil for this.
    def progress(requestId)
      result = nil
      @progressMutex.synchronize{ result = @requestProgress[requestId] }
      result
    end

    # Wait until the next result is ready. If this method is used it must always
    # be called before nextResult. This is mostly useful for testing.
    def wait
      @resultsSemaphore.wait
    end

    # Check if there are results ready. This method will return immediately
    # without blocking.
    def hasResults?
      ! @results.empty?
    end

    private
    def startThread
      @stopped = false
      @thread = Thread.new do
        QuartzTorrent.initThread("piecemanager")
        while ! @stopped
          begin
            @requestsSemaphore.wait

            if @requests.size > 1000
              @logger.warn "Request queue has grown past 1000 entries; we are io bound"
            end

            result = nil
            req = @requests.shift
            @progressMutex.synchronize{ @requestProgress[req[0]] = 0 }
            begin
              if req[1] == :read_block
                result = @pieceIO.readBlock req[2], req[3], req[4]
              elsif req[1] == :write_block
                @pieceIO.writeBlock req[2], req[3], req[4]
              elsif req[1] == :read_piece
                result = @pieceIO.readPiece req[2]
              elsif req[1] == :find_existing
                result = findExistingPiecesInternal(req[0])
              elsif req[1] == :hash_piece
                result = hashPiece req[2]
                result = Result.new(req[0], result, req[2])
              elsif req[1] == :flush
                @pieceIO.flush
                result = true
              end
              result = Result.new(req[0], true, result) if ! result.is_a?(Result)
            rescue
              @logger.error "Exception when processing request: #{$!}"
              @logger.error "#{$!.backtrace.join("\n")}"
              result = Result.new(req[0], false, nil, $!)
            end
            @progressMutex.synchronize{ @requestProgress[req[0]] = 100 }

            @mutex.synchronize do
              @results.push result
            end
            @resultsSemaphore.signal

            @alertCallback.call() if @alertCallback
          rescue
            @logger.error "Unexpected exception in PieceManager worker thread: #{$!}"
            @logger.error "#{$!.backtrace.join("\n")}"
          end
        end
      end
    end

    def returnAndIncrRequestId
      result = @requestId
      @requestId += 1
      # Wrap?
      @requestId = 0 if @requestId > 0xffffffff
      result
    end

    def findExistingPiecesInternal(requestId)
      completePieceBitfield = Bitfield.new(@torrinfo.pieces.length)
      raise "Base directory #{@baseDirectory} doesn't exist" if ! File.directory?(@baseDirectory)
      raise "Base directory #{@baseDirectory} is not writable" if ! File.writable?(@baseDirectory)
      raise "Base directory #{@baseDirectory} is not readable" if ! File.readable?(@baseDirectory)
      piecesHashes = @torrinfo.pieces
      index = 0
      piecesHashes.each do |hash|
        @logger.debug "Checking piece #{index+1}/#{piecesHashes.length}"
        piece = @pieceIO.readPiece(index)
        if piece
          # Check hash
          calc = Digest::SHA1.digest(piece)
          if calc != hash
            @logger.debug "Piece #{index} calculated hash #{QuartzTorrent.bytesToHex(calc)} doesn't match tracker hash #{QuartzTorrent.bytesToHex(hash)}"
          else
            completePieceBitfield.set(index)
            @logger.debug "Piece #{index+1}/#{piecesHashes.length} is complete."
          end
        else
          @logger.debug "Piece #{index+1}/#{piecesHashes.length} doesn't exist"
        end
        index += 1
        @progressMutex.synchronize{ @requestProgress[requestId] = (index+1)*100/piecesHashes.length }
      end
      completePieceBitfield
    end

    def hashPiece(pieceIndex)
      result = false
      piece = @pieceIO.readPiece pieceIndex
      if piece
        # Check hash
        piecesHashes = @torrinfo.pieces
        hash = piecesHashes[pieceIndex]
        calc = Digest::SHA1.digest(piece)
        if calc != hash
          @logger.info "Piece #{pieceIndex} calculated hash #{QuartzTorrent.bytesToHex(calc)} doesn't match tracker hash #{QuartzTorrent.bytesToHex(hash)}"
        else
          @logger.debug "Piece #{pieceIndex+1}/#{piecesHashes.length} hash is correct."
          result = true
        end
      else
        @logger.debug "Piece #{pieceIndex+1}/#{piecesHashes.length} doesn't exist"
      end
      result
    end
  end
end
