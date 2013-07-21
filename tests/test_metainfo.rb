#!/usr/bin/env ruby 
require 'rubygems'
require 'minitest/unit'
require 'minitest/autorun'
require 'src/metainfo'

TestDataDir = "tests/data"

class TestMetainfo < MiniTest::Unit::TestCase
  def setup
  end

  def testSingleFileTorrent
    metainfo = QuartzTorrent::Metainfo.createFromFile("#{TestDataDir}/Doctor.Who.2005.7x07.The.Rings.Of.Akhaten.HDTV.x264-FoV.%5Beztv%5D.torrent")
    assert_equal "Visit #EZTV on EFNet (irc.efnet.info) or http://eztv.it/", metainfo.comment
    creation = Time.utc(2013, 4, 6, 18, 57, 8)
    assert_equal creation, metainfo.creationDate
    assert_equal "udp://tracker.openbittorrent.com:80/", metainfo.announce
    assert_equal ["udp://tracker.openbittorrent.com:80"], metainfo.announceList[0]
    assert_equal 1, metainfo.info.files.size
    assert_equal "Doctor.Who.2005.7x07.The.Rings.Of.Akhaten.HDTV.x264-FoV.mp4", metainfo.info.files[0].path
    assert_equal "Doctor.Who.2005.7x07.The.Rings.Of.Akhaten.HDTV.x264-FoV.mp4", metainfo.info.name
    assert_equal 365280462, metainfo.info.files[0].length
    assert_equal 524288, metainfo.info.pieceLen
  end

  def testMultiFileTorrent
    metainfo = QuartzTorrent::Metainfo.createFromFile("#{TestDataDir}/testtorrent.torrent")
    assert_equal "http://localhost:8001/announce", metainfo.announce
    assert_equal "testtorrent", metainfo.info.name
    assert_equal 262144, metainfo.info.pieceLen
    assert_equal 2, metainfo.info.files.size
    assert_equal 15, metainfo.info.files[0].length
    assert_equal 15, metainfo.info.files[1].length
    assert_equal "testtorrent/file1", metainfo.info.files[0].path
    assert_equal "testtorrent/file2", metainfo.info.files[1].path

    #Decoded torrent metainfo: {"announce"=>"http://localhost/", "info"=>{"name"=>"testtorrent", "files"=>[{"path"=>["file1"], "length"=>15}, {"path"=>["file2"], "length"=>15}], "pieces"=>"\226qq\025e\327\376\277\324\322\275:\331`\375+d`\027A", "piece length"=>262144}, "creation date"=>1365789223}

  end
end


