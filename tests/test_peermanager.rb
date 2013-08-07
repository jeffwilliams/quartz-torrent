#!/usr/bin/env ruby 
$: << "."
require 'rubygems'
require 'minitest/unit'
require 'minitest/autorun'
require 'src/peermanager'
require 'src/trackerclient'
require 'src/peer'

include QuartzTorrent

class FakeRate
  def initialize(value)
    @value = value
  end
  attr_accessor :value
end

class TestPeerManager < MiniTest::Unit::TestCase
  def setup
  end

  def testFindRequestable

    peers = []
    ipnum = 0x01010101
    50.times do |i|
      # Convert ipnum to dotted-quad
      ip = [ipnum].pack("L>").unpack("CCCC").join(".")
      peer = Peer.new(TrackerPeer.new(ip,4000,"peer#{i}"))
      peer.uploadRate = FakeRate.new(0)
      peer.amChoked = false
      peer.state = :established
      peers.push peer
      ipnum += 1
    end

    #LogManager.logFile = 'stdout'
    #LogManager.setLevel "peer_manager", :debug

    # Make 10 peers interested
    peers.first(10).each do |peer|
      peer.peerInterested = true
    end

    peerManager = PeerManager.new
    
    classified = ClassifiedPeers.new(peers)
    manageResult = peerManager.managePeers(classified)

    manageResult.unchoke.each{ |peer| peer.peerChoked = false}
    manageResult.choke.each{ |peer| peer.peerChoked = true}

    # At most 4 peers are both interested and unchoked.
    count = peers.reduce(0){ |memo,v| v.peerInterested && ! v.peerChoked ? memo + 1 : memo }
    assert count <= 4, "More than 4 peers will be both interested and unchoked"
    
    # We may have 4 or 5 peers unchoked. If 5, then one is the optimistic unchoke which is not interested.
    assert manageResult.unchoke.length >= 4 && manageResult.unchoke.length <= 5
    assert_equal 0, manageResult.choke.length 

    #### PART 2
    # Make 4 peers that are interested but currently choked now have a better upload rate. These 4 peers should now
    # get unchoked, unless the optimistic unchoke peer turns out to be interested, in which case three of these
    # peers should be in the unchoked peers.
    classified = ClassifiedPeers.new(peers)

    changed = classified.chokedInterestedPeers.first(4)
    changed.each{ |peer| peer.uploadRate.value = 5}

    manageResult = peerManager.managePeers(classified)
    
    manageResult.unchoke.each{ |peer| peer.peerChoked = false}
    manageResult.choke.each{ |peer| peer.peerChoked = true}
       
    count = peers.reduce(0){ |memo,v| v.peerInterested && ! v.peerChoked ? memo + 1 : memo }
    assert count <= 4, "More than 4 peers will be both interested and unchoked"

    # We may have 4 or 5 peers unchoked. If 5, then one is the optimistic unchoke which is not interested.
    unchoked = peers.collect{ |p| (p.peerChoked) ? nil : p }.compact
    assert unchoked.length >= 4 && unchoked.length <= 5
    
    # At least 3 of the changed peers must be in the unchoked set.
    count = 0
    changed.each do |changedPeer|
      count += 1 if unchoked.reduce(false){ |memo, peer| memo || (peer.trackerPeer.id == changedPeer.trackerPeer.id) }
    end

    assert count >= 3, "Expected at least 3 of the peers unchoked to be the ones with higher upload rates, but only #{count} are."
    assert count <= 4
  
    #### PART 3
    # Pick 4 peers that are uninterested and currently choked and make them have a better upload rate. These 4 peers should now
    # get unchoked, but will not be interested.
    classified = ClassifiedPeers.new(peers)
    changed = classified.chokedUninterestedPeers.first(4)
    changed.each{ |peer| peer.uploadRate.value = 6}
  
    manageResult = peerManager.managePeers(classified)

    manageResult.unchoke.each{ |peer| peer.peerChoked = false}
    manageResult.choke.each{ |peer| peer.peerChoked = true}

    count = peers.reduce(0){ |memo,v| v.peerInterested && ! v.peerChoked ? memo + 1 : memo }
    assert count <= 4, "More than 4 peers will be both interested and unchoked"

    # We may have 8 or 9 peers unchoked. If 9, then one is the optimistic unchoke which is not interested.
    unchoked = peers.collect{ |p| (p.peerChoked) ? nil : p }.compact
    assert unchoked.length >= 8 && unchoked.length <= 9



  end

  
end


