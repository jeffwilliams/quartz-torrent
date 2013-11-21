#!/usr/bin/env ruby 
require 'minitest/unit'
require 'minitest/autorun'
require 'quartz_torrent/torrentqueue'

include QuartzTorrent

class FakeTorrentData
  def initialize(paused = false, queued = false, state = :running)
    @paused = paused
    @queued = queued
    @state = state
  end
  attr_accessor :paused, :queued, :state
end

class TestTorrentqueue < MiniTest::Unit::TestCase
  def setup
  end

  def testEmpty
    tq = TorrentQueue.new(5,10)
    assert_equal 0, tq.dequeue([]).size

    assert_equal 0, tq.dequeue([FakeTorrentData.new]).size
  end

  def testQueueOperationsChangeTorrentFlags
    tq = TorrentQueue.new(5,10)
    ft = FakeTorrentData.new(false,false,:running)
    assert !ft.queued
    tq.push ft
    assert ft.queued

    tq = TorrentQueue.new(5,10)
    ft = FakeTorrentData.new(false,false,:running)
    assert !ft.queued
    tq.unshift ft
    assert ft.queued
  end

  def testNoActiveAllIncomplete
    # All torrents are in queue, all incomplete, nothing running
    tq = TorrentQueue.new(4,10)

    torrents = [
      FakeTorrentData.new(false,true,:running),
      FakeTorrentData.new(false,true,:checking_pieces),
      FakeTorrentData.new(false,true,:downloading_metainfo),
      FakeTorrentData.new(false,true,:error),
    ]
    torrents.each{ |t| tq.push t }
    assert_equal 4, tq.dequeue(torrents).size

    # Check that we only dequeue 4 torrents even though >4 are in queue
    tq = TorrentQueue.new(4,10)
    torrents = [
      FakeTorrentData.new(false,true,:running),
      FakeTorrentData.new(false,true,:checking_pieces),
      FakeTorrentData.new(false,true,:downloading_metainfo),
      FakeTorrentData.new(false,true,:error),
      FakeTorrentData.new(false,true,:running),
    ]
    torrents.each{ |t| tq.push t }
    assert_equal 4, tq.dequeue(torrents).size
  end

  def testActivePoolFull
    # Test when the active pool is full no dequeuing happens
    tq = TorrentQueue.new(2,4)
    torrents = [
      FakeTorrentData.new(false,false,:running),
      FakeTorrentData.new(false,false,:checking_pieces),
      FakeTorrentData.new(false,false,:downloading_metainfo),
      FakeTorrentData.new(false,false,:error),
    ]
    to_queue = [
      FakeTorrentData.new(false,false,:running),
      FakeTorrentData.new(false,false,:checking_pieces),
      FakeTorrentData.new(false,false,:downloading_metainfo),
      FakeTorrentData.new(false,false,:error),
      FakeTorrentData.new(false,false,:uploading),
    ]

    to_queue.each{ |t| tq.push t }
    assert_equal 0, tq.dequeue(torrents).size


    tq = TorrentQueue.new(2,4)
    torrents = [
      FakeTorrentData.new(false,false,:uploading),
      FakeTorrentData.new(false,false,:uploading),
      FakeTorrentData.new(false,false,:uploading),
      FakeTorrentData.new(false,false,:uploading),
    ]
    to_queue = [
      FakeTorrentData.new(false,false,:uploading),
      FakeTorrentData.new(false,false,:uploading),
      FakeTorrentData.new(false,false,:running),
      FakeTorrentData.new(false,false,:uploading),
      FakeTorrentData.new(false,false,:uploading),
      FakeTorrentData.new(false,false,:uploading),
    ]

    to_queue.each{ |t| tq.push t }
    assert_equal 0, tq.dequeue(torrents).size
  end

  def testIncompletePoolFull
    # Test when the incomplete pool is full, no dequeuing happens if we only
    # have incomplete torrents in the queue
    tq = TorrentQueue.new(4,8)
    torrents = [
      FakeTorrentData.new(false,false,:running),
      FakeTorrentData.new(false,false,:running),
      FakeTorrentData.new(false,false,:running),
      FakeTorrentData.new(false,false,:running),
    ]
    to_queue = [
      FakeTorrentData.new(false,false,:running),
      FakeTorrentData.new(false,false,:checking_pieces),
      FakeTorrentData.new(false,false,:downloading_metainfo),
      FakeTorrentData.new(false,false,:error),
    ]

    to_queue.each{ |t| tq.push t }
    assert_equal 0, tq.dequeue(torrents).size

    # Test when the incomplete pool is full, we can still dequeue complete 
    # torrents
    
    tq = TorrentQueue.new(4,8)
    torrents = [
      FakeTorrentData.new(false,false,:running),
      FakeTorrentData.new(false,false,:running),
      FakeTorrentData.new(false,false,:running),
      FakeTorrentData.new(false,false,:running),
    ]
    to_queue = [
      FakeTorrentData.new(false,false,:uploading),
      FakeTorrentData.new(false,false,:uploading),
      FakeTorrentData.new(false,false,:running),
      FakeTorrentData.new(false,false,:checking_pieces),
      FakeTorrentData.new(false,false,:downloading_metainfo),
      FakeTorrentData.new(false,false,:uploading),
      FakeTorrentData.new(false,false,:uploading),
      FakeTorrentData.new(false,false,:uploading),
    ]
    to_queue.each{ |t| tq.push t }
    assert_equal 8, tq.size
    dequeued = tq.dequeue(torrents)
    assert_equal 4, dequeued.size
    dequeued.each do |t|
      assert_equal :uploading, t.state
    end
    assert_equal 4, tq.size
  
  end

  def testPauseUnpause
    tq = TorrentQueue.new(5,10)
    torrents = [
      FakeTorrentData.new(true,false,:running),
    ]
    torrents.first.paused = false  
    tq.push torrents.first
    assert_equal 1, tq.dequeue(torrents).size
  end
 
  def testUnqueueComplete
    tq = TorrentQueue.new(5,10)
    torrents = [
      FakeTorrentData.new(false,false,:uploading),
    ]
    tq.push torrents.first
    assert_equal 1, tq.dequeue(torrents).size


  end
  
end





