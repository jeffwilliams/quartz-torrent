#!/usr/bin/env ruby 
require 'rubygems'
require 'minitest/unit'
require 'minitest/autorun'
require 'quartz_torrent/semaphore.rb'

class TestSemaphore < MiniTest::Unit::TestCase
  def setup
  end

  def testSemaphore
    sem = Semaphore.new(3)
    mutex = Mutex.new 
    count = 0

    # Get the semaphore 3 times. count should increase to 3.
    t1 = Thread.new{ sem.wait; mutex.synchronize{ count += 1 } }
    t2 = Thread.new{ sem.wait; mutex.synchronize{ count += 1 } }
    t3 = Thread.new{ sem.wait; mutex.synchronize{ count += 1 } }
    t1.join
    t2.join
    t3.join
    assert_equal 3, count

    # Get the semaphore 1 more time. count should still be 3 since the thread wil have blocked.
    t = Thread.new{ sem.wait; count += 1 }
    assert_equal 3, count
  
    # Signal semaphore. Count should now move to 4.
    sem.signal
    t.join

    assert_equal 4, count
  end

  def testWaitWithTimeout
    sem = Semaphore.new

    # Test if we are not signalled
    rc = sem.wait(1)
    assert_equal 0, sem.count
    assert_equal false, rc
    
  
    # Test if we _are_ signalled before wait completes
    waitFinished = false
    rc = nil
    t1 = Thread.new do
      rc = sem.wait(10)
      waitFinished = true
    end
    sem.signal
    
    sleep 0.1 while ! waitFinished
    assert_equal 0, sem.count
    assert_equal true, rc
  end

end


