#!/usr/bin/env ruby 
require 'rubygems'
require 'minitest/unit'
require 'minitest/autorun'
require 'quartz_torrent/blockstate'
require 'quartz_torrent/metainfo'
require 'quartz_torrent/peer'

include QuartzTorrent

def makeMetaInfo(pieceLen, totalLength)

  numPieces = totalLength/pieceLen
  numPieces += 1 if totalLength%pieceLen > 0

  metainfo = Metainfo.new
  info = Metainfo::Info.new
  metainfo.info = info
  info.pieceLen = pieceLen
  metainfo.info.pieces = Array.new(numPieces,0)

  metainfo.info.files.push Metainfo::FileInfo.new(totalLength ,"/")

  metainfo
end

class TestBlockstate < MiniTest::Unit::TestCase
  def setup
    LogManager.logFile = "stdout"
    LogManager.setLevel "blockstate", :debug
  end

  def testFindRequestable

    # 256K pieces, total length = 100M. 400 pieces.
    metainfo = makeMetaInfo(256*1024, 100*1024*1024)
    # Make sure our makeMetaInfo calculated the number of pieces correctly; we expect it later in the test.
    assert_equal 400, metainfo.info.pieces.length
    numPieces = 400

    # Every even piece exists. Odd don't.
    initialBits = Bitfield.new(numPieces)
    numPieces.times do |i|
      if i % 2 == 0
        initialBits.set i
      else
        initialBits.clear i
      end
    end
    
    # Blocksize = 16K. 16 blocks per piece.
    blockstate = BlockState.new(metainfo, initialBits, 16*1024)

    # One peer has nothing
    peerNone = Peer.new(nil)
    peerNone.bitfield = Bitfield.new(numPieces)
    peerNone.bitfield.clearAll
    
    # One peer has all
    peerAll = Peer.new(nil)
    peerAll.bitfield = Bitfield.new(numPieces)
    peerAll.bitfield.setAll

    # One peer has first half of blocks
    peerFirstHalf = Peer.new(nil)
    peerFirstHalf.bitfield = Bitfield.new(numPieces)
    peerFirstHalf.bitfield.clearAll
    numPieces.times do |i|
      break if i >= 200
      peerFirstHalf.bitfield.set i
    end

    # One peer has middle half of blocks
    peerMiddleHalf = Peer.new(nil)
    peerMiddleHalf.bitfield = Bitfield.new(numPieces)
    peerMiddleHalf.bitfield.clearAll
    numPieces.times do |i|
      peerMiddleHalf.bitfield.set i if i >= 100 && i < 300
    end

    classifiedPeers = [peerNone, peerAll, peerFirstHalf, peerMiddleHalf]
    def classifiedPeers.requestablePeers
      self
    end

    start = Time.new
    blocks = blockstate.findRequestableBlocks(classifiedPeers, 10)
    diff = Time.new - start
    puts "Calculating blocks to request for torrent with 400 pieces (6400 blocks) with 4 peers took #{diff}s"

    assert_equal 10, blocks.size, "findRequestableBlocks returned wrong number of blocks"

    # The rarest blocks are the last 100 pieces. Our 10 blocks must come from there.
    blocks.each do |bl|
      assert bl.pieceIndex >= 300
      assert bl.pieceIndex < 400

      # Piece must be odd, because we have the even ones.
      assert bl.pieceIndex % 2 == 1

      # Only one peer has these rare pieces.
      assert_equal 1, bl.peers.size, "The number of peers calculated to have the piece is invalid"
      assert_equal peerAll, bl.peers.first
    end
  end

  
  def testFindRequestableBlockCalculations1

    # 100 byte pieces, total length = 105 bytes.
    metainfo = makeMetaInfo(100, 105)
    assert_equal 2, metainfo.info.pieces.length
    numPieces = 2

    # None of the torrent is downloaded.
    initialBits = Bitfield.new(numPieces)
    initialBits.clearAll
    
    # We have one peer with all of the torrent.
    peerAll = Peer.new(nil)
    peerAll.bitfield = Bitfield.new(numPieces)
    peerAll.bitfield.setAll
    
    classifiedPeers = [peerAll]
    def classifiedPeers.requestablePeers
      self
    end

    # Blocksize = 20 bytes. 5 blocks per piece.
    blockstate = BlockState.new(metainfo, initialBits, 20)

    blocks = blockstate.findRequestableBlocks(classifiedPeers, 10)
    assert_equal 6, blocks.size

    blocks.sort! do |a,b| 
      a.blockIndex <=> b.blockIndex
    end

    index = 0
    assert_equal 0, blocks[index].pieceIndex
    assert_equal 20, blocks[index].length
    assert_equal index*20, blocks[index].offset
    assert_equal index, blocks[index].blockIndex
    
    index = 1
    assert_equal 0, blocks[index].pieceIndex
    assert_equal 20, blocks[index].length
    assert_equal index*20, blocks[index].offset
    assert_equal index, blocks[index].blockIndex

    index = 2
    assert_equal 0, blocks[index].pieceIndex
    assert_equal 20, blocks[index].length
    assert_equal index*20, blocks[index].offset
    assert_equal index, blocks[index].blockIndex

    index = 3
    assert_equal 0, blocks[index].pieceIndex
    assert_equal 20, blocks[index].length
    assert_equal index*20, blocks[index].offset
    assert_equal index, blocks[index].blockIndex

    index = 4
    assert_equal 0, blocks[index].pieceIndex
    assert_equal 20, blocks[index].length
    assert_equal index*20, blocks[index].offset
    assert_equal index, blocks[index].blockIndex

    index = 5
    assert_equal 1, blocks[index].pieceIndex
    assert_equal 5, blocks[index].length
    assert_equal 0, blocks[index].offset
    assert_equal 5, blocks[index].blockIndex


  end

  def testFindRequestableBlockCalculations2

    # 100 byte pieces, total length = 120 bytes.
    metainfo = makeMetaInfo(100, 120)
    assert_equal 2, metainfo.info.pieces.length
    numPieces = 2

    # None of the torrent is downloaded.
    initialBits = Bitfield.new(numPieces)
    initialBits.clearAll
    
    # We have one peer with all of the torrent.
    peerAll = Peer.new(nil)
    peerAll.bitfield = Bitfield.new(numPieces)
    peerAll.bitfield.setAll
    
    classifiedPeers = [peerAll]
    def classifiedPeers.requestablePeers
      self
    end

    # Blocksize = 20 bytes. 5 blocks per piece.
    blockstate = BlockState.new(metainfo, initialBits, 20)

    blocks = blockstate.findRequestableBlocks(classifiedPeers, 10)
    assert_equal 6, blocks.size

    blocks.sort! do |a,b| 
      a.blockIndex <=> b.blockIndex
    end

    index = 0
    assert_equal 0, blocks[index].pieceIndex
    assert_equal 20, blocks[index].length
    assert_equal index*20, blocks[index].offset
    assert_equal index, blocks[index].blockIndex
    
    index = 1
    assert_equal 0, blocks[index].pieceIndex
    assert_equal 20, blocks[index].length
    assert_equal index*20, blocks[index].offset
    assert_equal index, blocks[index].blockIndex

    index = 2
    assert_equal 0, blocks[index].pieceIndex
    assert_equal 20, blocks[index].length
    assert_equal index*20, blocks[index].offset
    assert_equal index, blocks[index].blockIndex

    index = 3
    assert_equal 0, blocks[index].pieceIndex
    assert_equal 20, blocks[index].length
    assert_equal index*20, blocks[index].offset
    assert_equal index, blocks[index].blockIndex

    index = 4
    assert_equal 0, blocks[index].pieceIndex
    assert_equal 20, blocks[index].length
    assert_equal index*20, blocks[index].offset
    assert_equal index, blocks[index].blockIndex

    index = 5
    assert_equal 1, blocks[index].pieceIndex
    assert_equal 20, blocks[index].length
    assert_equal 0, blocks[index].offset
    assert_equal 5, blocks[index].blockIndex


  end

end

