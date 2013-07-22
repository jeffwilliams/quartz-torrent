require 'src/util'
require 'src/bitfield'

module QuartzTorrent
  
  class BlockInfo
    def initialize(pieceIndex, offset, length, peers, blockIndex)
      @pieceIndex = pieceIndex
      @offset = offset
      @length = length
      @peers = peers
      @blockIndex = blockIndex
    end
  
    attr_accessor :pieceIndex
    attr_accessor :offset
    attr_accessor :length
    attr_accessor :peers
    attr_accessor :blockIndex
  
    # Return a new Bittorrent Request message that requests this block.
    def getRequest
      m = Request.new
      m.pieceIndex = @pieceIndex
      m.blockOffset = @offset
      m.blockLength = @length
      m
    end
  end

  # Any given torrent is broken into pieces. Those pieces are broken into blocks.
  # This class can be used to keep track of which blocks are currently complete, which
  # have been requested but aren't available yet, and which are missing. 
  #
  # This class only supports one block size.
  class BlockState

    def initialize(metainfo, initialPieceBitfield, blockSize = 16384)
      raise "Block size cannot be <= 0" if blockSize <= 0

      @logger = LogManager.getLogger("blockstate")
  
      @pieceSize = metainfo.info.pieceLen
      @numPieces = metainfo.info.pieces.length
      @blocksPerPiece = (@pieceSize/blockSize + (@pieceSize%blockSize == 0 ? 0 : 1))
      @blockSize = blockSize
      # When calculating the number of blocks, the last piece is likely a partial piece...
      @numBlocks = @blocksPerPiece * (@numPieces-1)
      lastPieceLen = (metainfo.info.dataLength - (@numPieces-1)*@pieceSize)
      @numBlocks += lastPieceLen / @blockSize
      @numBlocks += 1 if lastPieceLen % @blockSize != 0
      @lastBlockLength = (metainfo.info.dataLength - (@numBlocks-1)*@blockSize)

      raise "Initial piece bitfield is the wrong length" if initialPieceBitfield.length != @numPieces


      @completeBlocks = Bitfield.new(@numBlocks)
      blockIndex = 0
      initialPieceBitfield.length.times do |pieceIndex|
        isSet = initialPieceBitfield.set?(pieceIndex)
        @blocksPerPiece.times do 
          # The last piece may be a smaller number of blocks.
          break if blockIndex >= @completeBlocks.length

          if isSet
            @completeBlocks.set blockIndex
          else
            @completeBlocks.clear blockIndex
          end
          blockIndex += 1
        end       
      end

      @requestedBlocks = Bitfield.new(@numBlocks)
      @requestedBlocks.clearAll
    end
 
    attr_reader :blockSize

    # Return a list of BlockInfo objects representing blocks that 
    # can be requested from peers that we need and aren't already requested.
    def findRequestableBlocks(classifiedPeers, numToReturn = nil)
      #@logger.debug "findRequestableBlocks: number of requestable peers: #{classifiedPeers.requestablePeers.size}"
      return [] if classifiedPeers.requestablePeers.size == 0

      # 0. Make a list of each peer having the specified piece
      peersHavingPiece = Array.new(@numPieces)
      # 1. Make a list of the rarity of pieces.
      rarity = Array.new(@numPieces,0)
      # This first list represents rarity by number if peers having that piece. 1 = rarest.
      classifiedPeers.requestablePeers.each do |peer|
        @numPieces.times do |i|
          if peer.bitfield.set?(i)
            rarity[i] += 1
            if peersHavingPiece[i]
              peersHavingPiece[i].push peer
            else
              peersHavingPiece[i] = [peer]
            end
          end
        end
      end

      # 2. Make a new list that indexes the first list by order of descending rarity.
      rarityOrder = Array.new(@numPieces)
      # The elements of this second list are pairs. The first element in the pair is the rarity, second is the piece index.
      @numPieces.times do |i|
        rarityOrder[i] = [rarity[i],i]
      end
      rarityOrder.sort!{ |a,b| a[0] <=> b[0] }
      # now second element of each pair 

      # 3. Randomize the list order within classes of the same rarity.
      left = 0
      leftVal = rarityOrder[left][0]
      @numPieces.times do |i|
        if rarityOrder[i][0] != leftVal
          # New range
          rangeLen = i-left+1
          
          arrayShuffleRange!(rarityOrder, left, rangeLen)           

          left = i+1
          leftVal = rarityOrder[left][0] if left < @numPieces
        end
      end
      arrayShuffleRange!(rarityOrder, left, @numPieces-left) if left < @numPieces
  
      # 3. Make a bitfield containing the pieces we want and haven't requested yet.
      requestable = @completeBlocks.union(@requestedBlocks).compliment!

      # 4. Rarest pieces first, find blocks that are available for download.
      result = []
      rarityOrder.each do |pair|
        pieceIndex = pair[1]
        eachBlockInPiece(pieceIndex) do |blockIndex|
          peersWithPiece = peersHavingPiece[pieceIndex]
          if requestable.set?(blockIndex) && peersWithPiece.size > 0
            # If this is the very last block, then it might be smaller than the rest.
            blockSize = @blockSize
            blockSize = @lastBlockLength if blockIndex == @numBlocks-1
            offsetWithinPiece = (blockIndex % @blocksPerPiece)*@blockSize
            result.push BlockInfo.new(pieceIndex, offsetWithinPiece, blockSize, peersHavingPiece[pieceIndex], blockIndex)
            break if numToReturn && result.size >= numToReturn
          end
        end
        break if numToReturn && result.size >= numToReturn
      end

      result
    end   
  end

  def setBlockRequested(blockInfo, bool)
    if bool
      @requestedBlocks.set blockInfo.blockIndex
    else
      @requestedBlocks.clear blockInfo.blockIndex
    end
  end

  # If this block completes the piece and a block is passed, the pieceIndex is yielded to the block.
  def setBlockCompleted(pieceIndex, blockOffset, bool, clearRequested = :clear_requested)
    bi = blockIndexFromPieceAndOffset(pieceIndex, blockOffset)
    @requestedBlocks.clear bi if clearRequested == :clear_requested
    if bool
      @completeBlocks.set bi
      yield pieceIndex if pieceCompleted?(pieceIndex) && block_given?
    else
      @completeBlocks.clear bi
    end
  end

  def setPieceCompleted(pieceIndex, bool)
    eachBlockInPiece(pieceIndex) do |blockIndex|
      if bool
        @completeBlocks.set blockIndex
      else
        @completeBlocks.clear blockIndex
      end
    end
  end

  private
  # Yield to a block each block index in a piece.
  def eachBlockInPiece(pieceIndex)
    (pieceIndex*@blocksPerPiece).upto(pieceIndex*@blocksPerPiece+@blocksPerPiece-1) do |blockIndex|
      break if blockIndex >= @numBlocks
      yield blockIndex
    end
  end

  def blockIndexFromPieceAndOffset(pieceIndex, blockOffset)
    pieceIndex*@blocksPerPiece + blockOffset/@blockSize
  end

  def pieceCompleted?(pieceIndex)
    complete = true
    eachBlockInPiece(pieceIndex) do |blockIndex|
      if ! @completeBlocks.set?(blockIndex)
        complete = false
        break
      end
    end 

    complete
  end
end

