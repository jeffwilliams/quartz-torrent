require 'quartz_torrent/util'
require 'quartz_torrent/filemanager'
require 'quartz_torrent/metainfo'
require "quartz_torrent/piecemanagerrequestmetadata.rb"
require "quartz_torrent/peerholder.rb"
require 'digest/sha1' 

# This class is used when we don't have the info struct for the torrent (no .torrent file) and must
# download it piece by piece from peers. It keeps track of the pieces we have.
#
# When a piece is requested from a peer and that peer responds with a reject saying it doesn't have
# that metainfo piece, we take a simple approach and mark that peer as bad, and don't request any more 
# pieces from that peer even though they may have other pieces. This simplifies the code.
module QuartzTorrent
  class MetainfoPieceState
    BlockSize = 16384
  
    # Create a new MetainfoPieceState that can be used to manage downloading the metainfo
    # for a torrent. The metainfo is stored in a file under baseDirectory named <infohash>.info,
    # where <infohash> is infoHash hex-encoded. The parameter metainfoSize should be the size of
    # the metainfo, and info can be used to pass in the complete metainfo Info object if it is available. This
    # is needed for when other peers request the metainfo from us.
    def initialize(baseDirectory, infoHash, metainfoSize, info = nil)
      
      @logger = LogManager.getLogger("metainfo_piece_state")

      @infoFileName = "#{bytesToHex(infoHash)}.info"

      if info 
        path = "#{baseDirectory}#{File::SEPARATOR}#{@infoFileName}"
        File.open(path, "w") do |file|
          bencoded = info.bencode
          metainfoSize = bencoded.length
          file.write bencoded
          # Sanity check
          testInfoHash = Digest::SHA1.digest( bencoded )
          raise "The computed infoHash #{bytesToHex(testInfoHash)} doesn't match the original infoHash #{bytesToHex(infoHash)}" if testInfoHash != infoHash
        end
      end

      # We use the PieceManager to manage the pieces of the metainfo file. The PieceManager is designed
      # for the pieces and blocks of actual torrent data, so we need to build a fake metainfo object that
      # describes our one metainfo file itself so that we can store the pieces if it on disk.
      # In this case we map metainfo pieces to 'torrent' pieces, and our blocks are the full length of the 
      # metainfo piece.
      torrinfo = Metainfo::Info.new
      torrinfo.pieceLen = BlockSize
      torrinfo.files = []
      torrinfo.files.push Metainfo::FileInfo.new(metainfoSize, @infoFileName)
    

      @pieceManager = PieceManager.new(baseDirectory, torrinfo)
      @pieceManagerRequests = {}

      @numPieces = metainfoSize/BlockSize
      @numPieces += 1 if (metainfoSize%BlockSize) != 0
      @completePieces = Bitfield.new(@numPieces)
      @completePieces.setAll if info 

      @lastPieceLength = metainfoSize - (@numPieces-1)*BlockSize
  
      @badPeers = PeerHolder.new
      @requestedPieces = Bitfield.new(@numPieces)
      @requestedPieces.clearAll
    end

    attr_accessor :infoFileName

    def pieceCompleted?(pieceIndex)
      @completePieces.set? pieceIndex
    end

    # Do we have all the pieces of the metadata?
    def complete?
      @completePieces.allSet?
    end

    def savePiece(pieceIndex, data)
      id = @pieceManager.writeBlock pieceIndex, 0, data
      @pieceManagerRequests[id] = PieceManagerRequestMetadata.new(:write, pieceIndex)
      id
    end

    def readPiece(pieceIndex)
      length = BlockSize
      length = @lastPieceLength if pieceIndex == @numPieces - 1
      id = @pieceManager.readBlock pieceIndex, 0, length
      #result = manager.nextResult
      @pieceManagerRequests[id] = PieceManagerRequestMetadata.new(:read, pieceIndex)
      id
    end

    # Check the results of savePiece and readPiece. This method returns a list
    # of the PieceManager results.
    def checkResults
      results = []
      while true
        result = @pieceManager.nextResult
        break if ! result

        results.push result
          
        metaData = @pieceManagerRequests.delete(result.requestId)
        if ! metaData
          @logger.error "Can't find metadata for PieceManager request #{result.requestId}"
          next
        end 

        if metaData.type == :write
          if result.successful?
            @completePieces.set(metaData.data)
          else
            @requestedPieces.clear(metaData.data)
            @logger.error "Writing metainfo piece failed: #{result.error}"
          end
        elsif metaData.type == :read
          if ! result.successful?
            @logger.error "Reading metainfo piece failed: #{result.error}"
          end
        end
      end
      results
    end

    def findRequestablePieces
      piecesRequired = []
      @numPieces.times do |pieceIndex|
        piecesRequired.push pieceIndex if ! @completePieces.set?(pieceIndex) && ! @requestedPieces.set?(pieceIndex)
      end

      piecesRequired
    end

    def findRequestablePeers(classifiedPeers)
      result = []

      classifiedPeers.establishedPeers.each do |peer|
        result.push peer if ! @badPeers.findByAddr(peer.trackerPeer.ip, peer.trackerPeer.port)
      end

      result
    end

    # Set whether the piece with the passed pieceIndex is requested or not.
    def setPieceRequested(pieceIndex, bool)
      if bool
        @requestedPieces.set pieceIndex
      else
        @requestedPieces.clear pieceIndex
      end
    end

    def markPeerBad(peer)
      @badPeers.add peer
    end

    # For debugging.
    def flush
      id = @pieceManager.flush
      @pieceManagerRequests[id] = PieceManagerRequestMetadata.new(:flush, nil)
      @pieceManager.wait
    end

    # Wait for the next a pending request to complete.
    def wait
      @pieceManager.wait
    end
  end
end
