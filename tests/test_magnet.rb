#!/usr/bin/env ruby 
require 'minitest/unit'
require 'minitest/autorun'
require 'quartz_torrent/magnet'

include QuartzTorrent

class TestMagnet < MiniTest::Unit::TestCase
  def setup
  end

  def testParse
    magnet = MagnetURI.new "magnet:?xt=urn:sha1:YNCKHTQCWBTRNJIV4WNAE52SJUQCZO5C"
    assert_equal "urn:sha1:YNCKHTQCWBTRNJIV4WNAE52SJUQCZO5C", magnet['xt'].first
    
    magnet = MagnetURI.new "magnet:?xt.1=urn:sha1:YNCKHTQCWBTRNJIV4WNAE52SJUQCZO5C&xt.2=urn:sha1:TXGCZQTH26NL6OUQAJJPFALHG2LTGBC7"
    assert_equal 2, magnet['xt'].length
    assert_equal "urn:sha1:YNCKHTQCWBTRNJIV4WNAE52SJUQCZO5C", magnet['xt'].first
    assert_equal "urn:sha1:TXGCZQTH26NL6OUQAJJPFALHG2LTGBC7", magnet['xt'][1]
  
    uri = "magnet:?xt=urn:btih:e149a18637eba5faeae21ecbc3c960c68dd9ab42&dn=Dig%21+-+2004&tr=udp%3A%2F%2Ftracker.openbittorrent.com%3A80&tr=udp%3A%2F%2Ftracker.publicbt.com%3A80&tr=udp%3A%2F%2Ftracker.istole.it%3A6969&tr=udp%3A%2F%2Ftracker.ccc.de%3A80&tr=udp%3A%2F%2Fopen.demonii.com%3A1337"

    magnet = MagnetURI.new uri
    infoHash = magnet.btInfoHash
    assert_equal 20, infoHash.length
    assert_equal 0xe1, infoHash[0,1].unpack("C")[0]
    assert_equal 0x49, infoHash[1,1].unpack("C")[0]
    assert_equal 0xa1, infoHash[2,1].unpack("C")[0]
    assert_equal 0x86, infoHash[3,1].unpack("C")[0]
    assert_equal 0x37, infoHash[4,1].unpack("C")[0]
    assert_equal 0xeb, infoHash[5,1].unpack("C")[0]
    assert_equal 0xa5, infoHash[6,1].unpack("C")[0]
    assert_equal 0xfa, infoHash[7,1].unpack("C")[0]
    assert_equal 0xea, infoHash[8,1].unpack("C")[0]
    assert_equal 0xe2, infoHash[9,1].unpack("C")[0]
    assert_equal 0x1e, infoHash[10,1].unpack("C")[0]
    assert_equal 0xcb, infoHash[11,1].unpack("C")[0]
    assert_equal 0xc3, infoHash[12,1].unpack("C")[0]
    assert_equal 0xc9, infoHash[13,1].unpack("C")[0]
    assert_equal 0x60, infoHash[14,1].unpack("C")[0]
    assert_equal 0xc6, infoHash[15,1].unpack("C")[0]
    assert_equal 0x8d, infoHash[16,1].unpack("C")[0]
    assert_equal 0xd9, infoHash[17,1].unpack("C")[0]
    assert_equal 0xab, infoHash[18,1].unpack("C")[0]
    assert_equal 0x42, infoHash[19,1].unpack("C")[0]
 
    assert_equal "Dig! - 2004", magnet["dn"].first
    assert_equal "udp://tracker.openbittorrent.com:80", magnet["tr"].first
    assert_equal "udp://tracker.publicbt.com:80", magnet["tr"][1]

  end

end




