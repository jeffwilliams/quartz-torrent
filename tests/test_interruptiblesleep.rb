#!/usr/bin/env ruby 
require 'rubygems'
require 'minitest/unit'
require 'minitest/autorun'
require 'src/interruptiblesleep'

class TestInterruptibleSleep < MiniTest::Unit::TestCase
  def setup
  end

  def testWake
    sleeper = QuartzTorrent::InterruptibleSleep.new
    
    woke = false

    Thread.new do
      sleeper.sleep 10
      woke = true
    end
  
    sleeper.wake
    sleep 1
    assert_equal true, woke

    # Test a second time with the same sleeper
    woke = false

    Thread.new do
      sleeper.sleep 10
      woke = true
    end

    sleeper.wake
    sleep 1
    assert_equal true, woke

    # Make sure sleeping works after waking
    start = Time.new
    sleeper.sleep 2
    dur = Time.new-start

    assert dur >= 2, "Sleep duration was #{dur} instead of 2 or more"
    
  end

  def testSleep
    sleeper = QuartzTorrent::InterruptibleSleep.new
    
    start = Time.new
    sleeper.sleep 2
    dur = Time.new-start

    assert dur >= 2, "Sleep duration was #{dur} instead of 2 or more"
  end

  def testWakeBeforeSleep
    sleeper = QuartzTorrent::InterruptibleSleep.new
    
    sleeper.wake

    woke = false
    Thread.new do
      sleeper.sleep 10
      woke = true
    end

    assert_equal false, woke
  end

end


