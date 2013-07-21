#!/usr/bin/env ruby 
require 'rubygems'
require 'minitest/unit'
require 'minitest/autorun'
require 'src/blockstate'
require 'src/metainfo'
require 'src/peer'

include QuartzTorrent

class TestBlockstate < MiniTest::Unit::TestCase
  def setup
  end

  def testFindRequestable
    metainfo = Metainfo.new
    info = Metainfo::Info.new
    metainfo.info = info
    # 256K
    info.pieceLen = 256*1024 
    numPieces = 400
    # 400 pieces of 256K = 100M.
    metainfo.info.pieces = Array.new(numPieces,0) 

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

end






