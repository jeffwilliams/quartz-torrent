#!/usr/bin/env ruby 
require 'rubygems'
require 'minitest/unit'
require 'minitest/autorun'
require 'fileutils'
require 'quartz_torrent/metainfo.rb'
require 'quartz_torrent/filemanager.rb'
require 'quartz_torrent/reactor.rb'

include QuartzTorrent

TestsDir = "tests"
TestDataDir = "tests/data"
TestDataTmpDir = "tests/data/tmp"

if ! File.directory?(TestDataTmpDir)
  FileUtils.mkdir TestDataTmpDir
end

class FileManagerReactorHandler < QuartzTorrent::Handler
  def initialize(fileManager)
    @fileManager = fileManager
  end

  def recvData(metadata)
  end

  def timerExpired(metadata)
  end

  def error(metadata, details)
  end
end

class TestFileManager < MiniTest::Unit::TestCase
  def setup
  end

  def testPieceMapper
    info = QuartzTorrent::Metainfo::Info.new
    info.pieceLen = 1024
    info.files = []
    info.files.push QuartzTorrent::Metainfo::FileInfo.new(2204, "download/file1")
    info.files.push QuartzTorrent::Metainfo::FileInfo.new(205, "download/file2")
    info.files.push QuartzTorrent::Metainfo::FileInfo.new(1800, "download/file3")
    info.files.push QuartzTorrent::Metainfo::FileInfo.new(1000, "download/file4")
    mapper = QuartzTorrent::PieceMapper.new("dl", info)

    result = mapper.findPiece(0)
    assert_equal 1, result.length
    assert_equal "dl/download/file1", result[0].path
    assert_equal 0, result[0].offset
    assert_equal 1024, result[0].length

    result = mapper.findPiece(1)
    assert_equal 1, result.length
    assert_equal "dl/download/file1", result[0].path
    assert_equal 1024, result[0].offset
    assert_equal 1024, result[0].length

    # Piece 2 overlaps 3 files: the end of file1, all of file2, and the beginning of file3.
    result = mapper.findPiece(2)
    assert_equal 3, result.length
    assert_equal "dl/download/file1", result[0].path
    assert_equal 2048, result[0].offset
    assert_equal 156, result[0].length
    assert_equal "dl/download/file2", result[1].path
    assert_equal 0, result[1].offset
    assert_equal 205, result[1].length
    assert_equal "dl/download/file3", result[2].path
    assert_equal 0, result[2].offset
    assert_equal 663, result[2].length

    result = mapper.findPiece(3)
    assert_equal 1, result.length
    assert_equal "dl/download/file3", result[0].path
    assert_equal 663, result[0].offset
    assert_equal 1024, result[0].length

    result = mapper.findPiece(4)
    assert_equal 2, result.length
    assert_equal "dl/download/file3", result[0].path
    assert_equal 1687, result[0].offset
    assert_equal 113, result[0].length
    assert_equal "dl/download/file4", result[1].path
    assert_equal 0, result[1].offset
    assert_equal 911, result[1].length
 
    result = mapper.findPiece(5)
    assert_equal 1, result.length
    assert_equal "dl/download/file4", result[0].path
    assert_equal 911, result[0].offset
    assert_equal 89, result[0].length

    # Test out of range.
    begin
      mapper.findPiece(99)
      flunk "Reading out of range piece didn't throw exception"
    rescue
    end
  end

  # Test that an empty torrent download directory is really treated as empty.
  def testEmptyTorrent
    LogManager.setup do
      setLogfile "stdout"
    end

    LogManager.setLevel "piecemanager", :debug
    metainfo = QuartzTorrent::Metainfo.createFromFile("#{TestDataDir}/testtorrent.torrent")
    manager = PieceManager.new(TestsDir, metainfo.info)
    manager.findExistingPieces
    manager.wait
    result = manager.nextResult
    assert_equal false, result.data.allSet?, "Empty torrent has all pieces completed."
  end

  # Test that a completed torrent directory has all the data.
  def testCompleteTorrent
    LogManager.setup do
      setLogfile "stdout"
    end
    LogManager.setLevel "piecemanager", :debug
    metainfo = QuartzTorrent::Metainfo.createFromFile("#{TestDataDir}/testtorrent.torrent")
    # Use tests/data as the base directory. Since the torrent contains testtorrent/file1 and testtorrent/file2,
    # and tests/data has the testtorrent directory containing those files, the torrent should seem complete.
    manager = PieceManager.new(TestDataDir, metainfo.info)
    id = manager.findExistingPieces
    manager.wait
    result = manager.nextResult
    assert_equal id, result.requestId, "Request id doesn't match response id"
    puts result.error if ! result.successful?
    puts "Bitfield: " + result.data.to_s
    assert_equal true, result.data.allSet?, "Complete torrent has not all pieces completed."
  end

  def testCopy
    LogManager.setup do
      setLogfile "stdout"
    end
    LogManager.setLevel "piecemanager", :debug
    LogManager.setLevel "piecemapper", :debug
    metainfo = QuartzTorrent::Metainfo.createFromFile("#{TestDataDir}/testtorrent.torrent")

    completeManager = PieceManager.new(TestDataDir, metainfo.info)

    incompleteDir = TestDataTmpDir + File::SEPARATOR + "testtorrent"
    if File.exists? incompleteDir
      puts "Removing directory #{incompleteDir}"
      FileUtils.rm_r incompleteDir
    end
    incompleteManager = PieceManager.new(TestDataTmpDir, metainfo.info)

    # Starting with a complete torrent and an empty torrent, read blocks from the complete and write them to the 
    # empty until the empty is complete. Then load it and confirm it is complete.
    blockSize = 4 

    puts "Copying torrent data from #{TestDataDir} to #{incompleteDir}"

    metainfo.info.pieces.length.times do |i|
      thisPieceLen = metainfo.info.pieceLen
      # Hack for this test.
      thisPieceLen = incompleteManager.torrentDataLength if thisPieceLen > incompleteManager.torrentDataLength

      numblocks = thisPieceLen/blockSize + (thisPieceLen % blockSize == 0 ? 0 : 1)
      numblocks.times do |j|
        id = completeManager.readBlock(i,j,blockSize)
        completeManager.wait
        result = completeManager.nextResult
        assert_equal id, result.requestId, "Request id doesn't match response id"
        
        incompleteManager.writeBlock(i,j,result.data)
      end
    end
    incompleteManager.wait

    puts "Checking copied data "

    manager = PieceManager.new(TestDataDir, metainfo.info)
    manager.findExistingPieces
    manager.wait
    result = manager.nextResult
    puts result.error if ! result.successful?
    puts "Bitfield: " + result.data.to_s
    assert_equal true, result.data.allSet?, "Copying using PieceManager failed: complete torrent has not all pieces completed."

  end

  def testStop
    LogManager.setup do
      setLogfile "stdout"
    end
    LogManager.setLevel "piecemanager", :debug
    LogManager.setLevel "piecemapper", :debug
    metainfo = QuartzTorrent::Metainfo.createFromFile("#{TestDataDir}/testtorrent.torrent")
    threadcount = Thread.list.size
    manager = PieceManager.new(TestDataTmpDir, metainfo.info)
    assert_equal threadcount+1, Thread.list.size, "After starting PieceManager I expected to have 2 threads running, but there are #{Thread.list.size}. #{Thread.list.size > 2 ? "It seems like threads from other tests are still running... try this one in isolation": "Maybe test has a race condition."}"
    manager.stop
    manager.wait
    assert_equal threadcount, Thread.list.size
  end

end

