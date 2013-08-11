#!/usr/bin/env ruby 
require 'rubygems'
require 'minitest/unit'
require 'minitest/autorun'
require 'quartz_torrent/bitfield'

class TestBitfield < MiniTest::Unit::TestCase
  def setup
  end

  def testCreate
    bf = QuartzTorrent::Bitfield.new(0)
    assert_equal 0, bf.length
    bf = QuartzTorrent::Bitfield.new(1)
    assert_equal 1, bf.length
  end

  def testSetAndClear
    bf = QuartzTorrent::Bitfield.new(16)
  
    (0..15).each do |b|
      bf.set(b)
      assert bf.set?(b)
      bf.clear(b)
      assert !bf.set?(b)
    end

    (0..15).each do |b|
      assert !bf.set?(b)
    end
  end

  def testSerializeAndUnserialize
    bf = QuartzTorrent::Bitfield.new(16)
    assert_equal 2, bf.byteLength
    s = bf.serialize   
    assert_equal 2, s.length
    # Test that an uninitialized bitfield is all 0s
    assert_equal 0, s[0,1].unpack("C")[0]
    assert_equal 0, s[1,1].unpack("C")[0]
    
    # First byte: 10101010 = 0xAA
    bf.set(0)
    bf.set(2)
    bf.set(4)
    bf.set(6)

    # Second byte: 01010101 = 0x55
    bf.set(9)
    bf.set(11)
    bf.set(13)
    bf.set(15)

    s = bf.serialize   
    assert_equal 2, s.length
    comp = [0xAA,0x55].pack("CC")
    assert_equal comp, s

    
    # First byte: 10000001 = 0x81
    # Second byte: 11110000 = 0xF0
    s = [0x81, 0xF0].pack("CC")
    bf.unserialize(s)
    assert bf.set?(0)
    assert !bf.set?(1)
    assert !bf.set?(2)
    assert !bf.set?(3)
    assert !bf.set?(4)
    assert !bf.set?(5)
    assert !bf.set?(6)
    assert bf.set?(7)

    assert bf.set?(8)
    assert bf.set?(9)
    assert bf.set?(10)
    assert bf.set?(11)
    assert !bf.set?(12)
    assert !bf.set?(13)
    assert !bf.set?(14)
    assert !bf.set?(15)
  end

  def testAllSet
    bf = QuartzTorrent::Bitfield.new(16)
    assert ! bf.allSet?
  
    16.times{ |i| bf.set i }
    assert bf.allSet?
    bf.clear 7
    assert !bf.allSet?
    bf.clear 13
    assert !bf.allSet?

    bf = QuartzTorrent::Bitfield.new(5)
    5.times{ |i| bf.set i }
    assert bf.allSet?, "A 5-bit bitset has all bits set but it allSet? returns false"

    bf = QuartzTorrent::Bitfield.new(13)
    13.times{ |i| bf.set i }
    assert bf.allSet?, "A 13-bit bitset has all bits set but it allSet? returns false"
    bf.clear 11
    assert !bf.allSet?
  end

  def testAllClear
    bf = QuartzTorrent::Bitfield.new(16)
    assert bf.allClear?
  
    16.times{ |i| bf.set i }
    assert !bf.allClear?
    bf.clear 7
    assert !bf.allClear?
    bf.clear 13
    assert !bf.allClear?

    bf = QuartzTorrent::Bitfield.new(5)
    5.times{ |i| bf.set i }
    assert !bf.allClear?, "A 5-bit bitset has all bits set but it allSet? returns false"

    bf = QuartzTorrent::Bitfield.new(13)
    assert bf.allClear?
    bf.set 12
    assert !bf.allClear?
  end

  def testFill
    bf = QuartzTorrent::Bitfield.new(10)
    bf.setAll
    
    assert bf.allSet?

    bf.clearAll

    10.times do |i|
      assert ! bf.set?(i)
    end

  end

  def testUnion
    bf1 = QuartzTorrent::Bitfield.new(11)
    bf2 = QuartzTorrent::Bitfield.new(11)

    bf1.set(0)
    bf1.clear(1)
    bf1.set(2)
    bf1.set(3)
    bf1.clear(4)

    bf1.set(8)
    bf1.set(9)
    bf1.clear(10)
    bf1.clear(11)

    bf2.set(0)
    bf2.clear(1)
    bf2.clear(2)
    bf2.set(3)
    bf2.set(4)

    bf2.set(8)
    bf2.clear(9)
    bf2.set(10)
    bf2.clear(11)

    bf3 = bf1.union(bf2)

    assert bf3.set?(0)
    assert !bf3.set?(1)
    assert bf3.set?(2)
    assert bf3.set?(3)
    assert bf3.set?(4)

    assert bf3.set?(8)
    assert bf3.set?(9)
    assert bf3.set?(10)
    assert !bf3.set?(11)

  end

  def testCompliment
    bf1 = QuartzTorrent::Bitfield.new(11)

    bf1.set(0)
    bf1.clear(1)
    bf1.set(2)
    bf1.set(3)
    bf1.clear(4)

    bf1.set(8)
    bf1.set(9)
    bf1.clear(10)
    bf1.clear(11)

    bf1.compliment!

    assert !bf1.set?(0)
    assert bf1.set?(1)
    assert !bf1.set?(2)
    assert !bf1.set?(3)
    assert bf1.set?(4)

    assert !bf1.set?(8)
    assert !bf1.set?(9)
    assert bf1.set?(10)
    assert bf1.set?(11)

  end
end




