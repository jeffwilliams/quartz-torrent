#!/usr/bin/env ruby 
require 'rubygems'
require 'minitest/unit'
require 'minitest/autorun'
require 'quartz_torrent/trackerclient'

TestDataDir = "tests/data"

class TestHttpTrackerDriver < QuartzTorrent::HttpTrackerDriver
  def initialize
    super(nil, nil)
  end

  def testDecodePeers(p)
    decodePeers(p)
  end
end

class SimpleTestTrackerDriver < QuartzTorrent::TrackerDriver
  def initialize(requestCallback)
    @requestCallback = requestCallback
  end

  def request(event = nil)
    @requestCallback.call event
    peer = QuartzTorrent::TrackerPeer.new("127.0.0.1",6556)
    resp = QuartzTorrent::TrackerResponse.new(true, nil, [peer])
    resp.interval = 1
    resp
  end
end

class TrackerTestClient < QuartzTorrent::TrackerClient
  def initialize(requestCallback)
    super("http://localhost:9999/announce", nil)
    @driver = SimpleTestTrackerDriver.new(requestCallback)
  end

  def currentDriver
    @driver
  end
end

class TestTrackerClient < MiniTest::Unit::TestCase
  def setup
  end

  def testTrackerResponsePeerParsing
    compactPeers = [127,0,0,1,1000, 127,0,0,2,2002].pack("CCCCnCCCCn")

    testTracker = TestHttpTrackerDriver.new
    peers = testTracker.testDecodePeers(compactPeers)
 
    assert_equal 2, peers.length
    assert_equal "127.0.0.1", peers[0].ip
    assert_equal 1000, peers[0].port
    assert_equal "127.0.0.2", peers[1].ip
    assert_equal 2002, peers[1].port
  end

  def testPack
    num = 0x0102030405060708
    result = QuartzTorrent::UdpTrackerMessage.packAsNetworkOrder(num, 8)

    assert_equal 8, result.length

    assert_equal 1, result[0,1].unpack("C")[0]
    assert_equal 2, result[1,1].unpack("C")[0]
    assert_equal 3, result[2,1].unpack("C")[0]
    assert_equal 4, result[3,1].unpack("C")[0]
    assert_equal 5, result[4,1].unpack("C")[0]
    assert_equal 6, result[5,1].unpack("C")[0]
    assert_equal 7, result[6,1].unpack("C")[0]
    assert_equal 8, result[7,1].unpack("C")[0]

    num = 55
    result = QuartzTorrent::UdpTrackerMessage.packAsNetworkOrder(num,8)

    assert_equal 8, result.length

    assert_equal 0, result[0,1].unpack("C")[0]
    assert_equal 0, result[1,1].unpack("C")[0]
    assert_equal 0, result[2,1].unpack("C")[0]
    assert_equal 0, result[3,1].unpack("C")[0]
    assert_equal 0, result[4,1].unpack("C")[0]
    assert_equal 0, result[5,1].unpack("C")[0]
    assert_equal 0, result[6,1].unpack("C")[0]
    assert_equal 55, result[7,1].unpack("C")[0]

    num = -1
    # -1 as a 64-bit integer in twos compliment is 
    # = 0xFFFFFFFFFFFFFFFE + 1 (ones compliment + 1)
    # = 0xFFFFFFFFFFFFFFFF
    result = QuartzTorrent::UdpTrackerMessage.packAsNetworkOrder(num,8)

    assert_equal 8, result.length

    assert_equal 0xff, result[0,1].unpack("C")[0]
    assert_equal 0xff, result[1,1].unpack("C")[0]
    assert_equal 0xff, result[2,1].unpack("C")[0]
    assert_equal 0xff, result[3,1].unpack("C")[0]
    assert_equal 0xff, result[4,1].unpack("C")[0]
    assert_equal 0xff, result[5,1].unpack("C")[0]
    assert_equal 0xff, result[6,1].unpack("C")[0]
    assert_equal 0xff, result[7,1].unpack("C")[0]
  end

  def testUnpack
    num = 0x0102030405060708
    str = QuartzTorrent::UdpTrackerMessage.packAsNetworkOrder(num,8)
    num = QuartzTorrent::UdpTrackerMessage.unpackNetworkOrder(str)
    assert_equal 0x0102030405060708, num

    num = -1
    str = QuartzTorrent::UdpTrackerMessage.packAsNetworkOrder(num,8)
    num = QuartzTorrent::UdpTrackerMessage.unpackNetworkOrder(str)
    assert_equal -1, num

    num = -345094365
    str = QuartzTorrent::UdpTrackerMessage.packAsNetworkOrder(num,8)
    num = QuartzTorrent::UdpTrackerMessage.unpackNetworkOrder(str)
    assert_equal -345094365, num
  end

  def testPackUnpackSizes
    num = 4000
    str = QuartzTorrent::UdpTrackerMessage.packAsNetworkOrder(num,2)
    num = QuartzTorrent::UdpTrackerMessage.unpackNetworkOrder(str)
    assert_equal 2, str.length
    assert_equal 4000, num

    num = 4000
    str = QuartzTorrent::UdpTrackerMessage.packAsNetworkOrder(num,4)
    num = QuartzTorrent::UdpTrackerMessage.unpackNetworkOrder(str)
    assert_equal 4, str.length
    assert_equal 4000, num

    num = 4000
    str = QuartzTorrent::UdpTrackerMessage.packAsNetworkOrder(num,4)
    num = QuartzTorrent::UdpTrackerMessage.unpackNetworkOrder(str,4)
    assert_equal 4000, num
  end

  def testEventSending
    state = :first
    requestCount = 0
    stopSent = false
    completedSent = false

    callback = Proc.new do |event|
      requestCount += 1
      if event == :stopped
        stopSent = true
      elsif event == :completed
        completedSent = true
      else
        flunk "Received a non-stop event after a stop was already sent" if stopSent
        if state == :first
          assert_equal :started, event, "First event was not 'started'"
          state = :inter
        elsif state == :inter
          assert_nil event, "Event after first was #{event} when it should have been nil"
        end
      end
    end

    client = TrackerTestClient.new callback
    client.start
    sleep 2
    client.completed
    sleep 1
    client.stop
    sleep 2
    assert_equal true, stopSent, "Stop event was never sent"
    assert_equal true, completedSent, "Completed event was never sent"
    assert requestCount >= 3, "Too few events"
    
  end
end



