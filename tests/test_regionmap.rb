#!/usr/bin/env ruby 
require 'rubygems'
require 'minitest/unit'
require 'minitest/autorun'
require 'quartz_torrent/regionmap.rb'

class TestRegionMap < MiniTest::Unit::TestCase
  def setup
  end

  def testBinsearch
    a = [3,5,8,10,13]

    assert_equal 3, a.binsearch{ |x| x >= 0 }
    assert_equal 3, a.binsearch{ |x| x >= 1 }
    assert_equal 3, a.binsearch{ |x| x >= 2 }
    assert_equal 3, a.binsearch{ |x| x >= 3 }
    assert_equal 5, a.binsearch{ |x| x >= 4 }
    assert_equal 5, a.binsearch{ |x| x >= 5 }
    assert_equal 8, a.binsearch{ |x| x >= 6 }
    assert_equal 8, a.binsearch{ |x| x >= 7 }
    assert_equal 8, a.binsearch{ |x| x >= 8 }
    assert_equal 10, a.binsearch{ |x| x >= 9 }
    assert_equal 10, a.binsearch{ |x| x >= 10 }
    assert_equal 13, a.binsearch{ |x| x >= 11 }
    assert_equal 13, a.binsearch{ |x| x >= 13 }
    assert_nil a.binsearch{ |x| x >= 14 }
  end

  def testBasic
    map = QuartzTorrent::RegionMap.new
   
    # a: 0-30
    # b: 31-40
    # c: 40-99

    map.add(30, "a")
    map.add(40, "b")
    map.add(99, "c")
 
    assert_equal "a", map.findValue(0)
    assert_equal "a", map.findValue(15)
    assert_equal "a", map.findValue(30)
    assert_equal "b", map.findValue(31)
    assert_equal "b", map.findValue(36)
    assert_equal "b", map.findValue(40)
    assert_equal "c", map.findValue(41)
    assert_equal "c", map.findValue(70)
    assert_equal "c", map.findValue(99)

  end

  def testIndex
    map = QuartzTorrent::RegionMap.new
   
    # a: 0-30
    # b: 31-40
    # c: 40-99

    map.add(30, "a")
    map.add(40, "b")
    map.add(99, "c")
 
    assert_equal 0, map.findIndex(0)
    assert_equal 0, map.findIndex(15)
    assert_equal 0, map.findIndex(30)
    assert_equal 1, map.findIndex(31)
    assert_equal 1, map.findIndex(36)
    assert_equal 1, map.findIndex(40)
    assert_equal 2, map.findIndex(41)
    assert_equal 2, map.findIndex(70)
    assert_equal 2, map.findIndex(99)

  end

  def testIndexAndOffset
    map = QuartzTorrent::RegionMap.new
   
    # a: 0-30
    # b: 31-40
    # c: 40-99

    map.add(30, "a")
    map.add(40, "b")
    map.add(99, "c")
 
    #[index, value, left, right, offset]
    index, value, left, right, offset = map.find(0)
    assert_equal 0, index
    assert_equal "a", value
    assert_equal 0, left
    assert_equal 30, right
    assert_equal 0, offset

    index, value, left, right, offset = map.find(15)
    assert_equal 0, index
    assert_equal "a", value
    assert_equal 0, left
    assert_equal 30, right
    assert_equal 15, offset


    index, value, left, right, offset = map.find(30)
    assert_equal 0, index
    assert_equal "a", value
    assert_equal 0, left
    assert_equal 30, right
    assert_equal 30, offset


    index, value, left, right, offset = map.find(31)
    assert_equal 1, index
    assert_equal "b", value
    assert_equal 31, left
    assert_equal 40, right
    assert_equal 0, offset

    index, value, left, right, offset = map.find(36)
    assert_equal 1, index
    assert_equal "b", value
    assert_equal 31, left
    assert_equal 40, right
    assert_equal 5, offset

    index, value, left, right, offset = map.find(40)
    assert_equal 1, index
    assert_equal "b", value
    assert_equal 31, left
    assert_equal 40, right
    assert_equal 9, offset

  end

  def testLast
    map = QuartzTorrent::RegionMap.new
    # a: 0-30
    # b: 31-40
    # c: 40-99

    map.add(30, "a")
    map.add(40, "b")
    map.add(99, "c")

    index, value, left, right = map.last
    assert_equal 2, index
    assert_equal "c", value
    assert_equal 41, left
    assert_equal 99, right

  end
end
