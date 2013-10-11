#!/usr/bin/env ruby 
require 'rubygems'
require 'minitest/unit'
require 'minitest/autorun'
require 'quartz_torrent/util'

include QuartzTorrent

class TestUtil < MiniTest::Unit::TestCase
  def setup
  end

  def testShuffle
    # This mostly just tests for out of range errors.

    a = [0,1,2,3,4,5]

    begin
      QuartzTorrent::arrayShuffleRange!(a, 0, 6)
    rescue
      flunk "Got exception #{$!} when not expected"
    end

    begin
      QuartzTorrent::arrayShuffleRange!(a, 0, 7)
      flunk
    rescue
    end

    begin
      QuartzTorrent::arrayShuffleRange!(a, 1, 6)
      flunk
    rescue
    end

    begin
      QuartzTorrent::arrayShuffleRange!(a, 0, 3)
    rescue
      flunk
    end

    begin
      QuartzTorrent::arrayShuffleRange!(a, 3, 3)
    rescue
      flunk
    end
  end

end





