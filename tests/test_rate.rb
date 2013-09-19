#!/usr/bin/env ruby 
require 'minitest/unit'
require 'minitest/autorun'
require 'quartz_torrent/rate'

include QuartzTorrent

class TestRateLimit < MiniTest::Unit::TestCase
  def setup
  end

  def testNoSamples
    r = Rate.new
    assert_equal 0.0, r.value
  end

  def testOneSecond
    r = Rate.new
    sleep 1
    r.update 100
    assert r.value > 90
    assert r.value < 110
  end

  def testReset
    r = Rate.new
    sleep 1
    r.update 100
    r.reset
    assert_equal 0.0, r.value
  end

end






