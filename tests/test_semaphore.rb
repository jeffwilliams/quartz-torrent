#!/usr/bin/env ruby 
require 'rubygems'
require 'minitest/unit'
require 'minitest/autorun'
require './src/semaphore.rb'

class TestSemaphore < MiniTest::Unit::TestCase
  def setup
  end

  def testSemaphore
    sem = Semaphore.new(3)
    count = 0

    # Get the semaphore 3 times. count should increase to 3.
    Thread.new{ sem.wait; count += 1 }
    Thread.new{ sem.wait; count += 1 }
    Thread.new{ sem.wait; count += 1 }
    assert_equal 3, count

    # Get the semaphore 1 more time. count should still be 3 since the thread wil have blocked.
    Thread.new{ sem.wait; count += 1 }
    assert_equal 3, count
  
    # Signal semaphore. Count should now move to 4.
    sem.signal
    sleep 0.4

    assert_equal 4, count
  end

end


