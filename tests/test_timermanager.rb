#!/usr/bin/env ruby 
require 'minitest/unit'
require 'minitest/autorun'
require 'quartz_torrent/timermanager'

include QuartzTorrent

class TestBlockstate < MiniTest::Unit::TestCase
=begin
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
=end

  def testOrder
    mgr = TimerManager.new
    mgr.add(3, :timer0, false, true)
    mgr.add(1, :timer1, false, false)
    mgr.add(1.1, :timer2, false, false)
    mgr.add(1.2, :timer3, false, false)
    
    assert_equal :timer0, mgr.next.metainfo
    assert_equal :timer1, mgr.next.metainfo
    assert_equal :timer2, mgr.next.metainfo
    assert_equal :timer3, mgr.next.metainfo
  end

  def testTimerLoss
  
    mgr = TimerManager.new

    countWritten = 0
    countRead = 0
  
    stopWriting = false
    stopReading = false
    writingStopped = false

    t1 = Thread.new do
      while ! stopReading || ! mgr.empty?
        t = mgr.peek if rand(2) == 0
        t = mgr.next
        countRead += 1 if t
      end
    end

    t2 = Thread.new do
      while ! stopWriting
        mgr.add(1, :timer, false, false)
        mgr.add(1, :timer, false, true)
        mgr.add_cancelled(1, :timer, false, true)
        mgr.add_cancelled(2, :timer, false, false)
        countWritten += 2 # We will only read the non-cancelled ones
      end
      writingStopped = true
    end
  
    sleep 1
    stopWriting = true
    sleep 0.1 while ! writingStopped
    stopReading = true

    assert_equal countWritten, countRead
    puts "#{countWritten} timers"

  end

end


