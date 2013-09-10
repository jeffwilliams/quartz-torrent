#!/usr/bin/env ruby 
require 'minitest/unit'
require 'minitest/autorun'
require 'quartz_torrent/ratelimit'

class TestRateLimit < MiniTest::Unit::TestCase
  def setup
  end

  def testOne
    limit = RateLimit.new(2.0, 10, 0)
    sleep 2
    avail = limit.avail
    assert avail > 4.0, "Avail should be > 6, but is #{avail}"
    assert avail < 4.5, "Avail should be < 6.5, but is #{avail}"
  end

  def testTwo
    limit = RateLimit.new(2.0, 5, 0)
    sleep 3
    avail = limit.avail
    assert avail >= 5.0, "Avail should be = 5, but is #{avail}"
    assert avail <= 5.0, "Avail should be = 5, but is #{avail}"
  end

  def testThree
    limit = RateLimit.new(2.0, 10, 0)
    sleep 2
    limit.withdraw 3
    avail = limit.avail
    assert avail >= 1.0, "Avail should be >= 1, but is #{avail}"
    assert avail <= 1.5, "Avail should be <= 1.5, but is #{avail}"
  end

end





