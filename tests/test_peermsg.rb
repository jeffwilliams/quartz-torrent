#!/usr/bin/env ruby 
require 'minitest/unit'
require 'minitest/autorun'
require 'quartz_torrent/peermsg'

include QuartzTorrent

class TestPeerMsg < MiniTest::Unit::TestCase
  def setup
  end

  def testExtendedMetainfoRequest
    encoded = {'msg_type' => 0, 'piece' => 0}.bencode
    # Since the ExtendedMetaInfo is an Extended message, we have to put a one-byte extended message
    # type at the beginning.
    encoded = '0' + encoded

    msg = ExtendedMetaInfo.new   
    msg.unserialize encoded

    assert_equal :request, msg.msgType
    assert_equal 0, msg.piece
  end

  def testExtendedMetainfoPiece
    encoded = {'msg_type' => 1, 'piece' => 0, 'total_size' => 7}.bencode
    # Since the ExtendedMetaInfo is an Extended message, we have to put a one-byte extended message
    # type at the beginning.
    encoded = '0' + encoded
    # Our data piece.
    data = "my data"
    encoded << data

    msg = ExtendedMetaInfo.new   
    msg.unserialize encoded

    assert_equal :piece, msg.msgType
    assert_equal 0, msg.piece
    assert_equal 7, msg.totalSize
    assert_equal data, msg.data
  end

  def testExtendedMetainfoReject
    encoded = {'msg_type' => 2, 'piece' => 0}.bencode
    # Since the ExtendedMetaInfo is an Extended message, we have to put a one-byte extended message
    # type at the beginning.
    encoded = '0' + encoded

    msg = ExtendedMetaInfo.new   
    msg.unserialize encoded

    assert_equal :reject, msg.msgType
    assert_equal 0, msg.piece


  end

end





