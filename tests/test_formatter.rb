#!/usr/bin/env ruby 
require 'minitest/unit'
require 'minitest/autorun'
require 'quartz_torrent/formatter'

include QuartzTorrent

class TestFormatter < MiniTest::Unit::TestCase
  def setup
  end

  def testFormatSize
    assert_equal "0.00B", Formatter.formatSize(0)
    assert_equal "100.00B", Formatter.formatSize(100)
    assert_equal "1.00KB", Formatter.formatSize(1024)
    assert_equal "1.46KB", Formatter.formatSize(1500)
    assert_equal "1.00MB", Formatter.formatSize(1048576)
    assert_equal "1.00GB", Formatter.formatSize(1048576*1024)
  end

  def testParseSize
    assert_equal 100, Formatter.parseSize("100")
    assert_equal 100, Formatter.parseSize("100B")
    assert_equal 100, Formatter.parseSize("100 B")
    assert_equal 100, Formatter.parseSize("100.0 B")
    assert_equal 100, Formatter.parseSize("100.000 b")

    assert_equal 102400, Formatter.parseSize("100KB")
    assert_equal 102400, Formatter.parseSize("100 KB")
    assert_equal 102400, Formatter.parseSize("100.0 KB")
    assert_equal 102400, Formatter.parseSize("100.000 kb")
    assert_equal 102400, Formatter.parseSize("  100.000 kb")

    assert_equal 1048576, Formatter.parseSize("1.000 Mb")
    assert_equal 1048576*1024, Formatter.parseSize("1.000 Gb")

  end

end





