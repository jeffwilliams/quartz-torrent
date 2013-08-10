require 'thread'

module QuartzTorrent
  # Class that implements a sleep for a specified number of seconds that can be interrupted.
  # When a caller calls sleep, another thread can call wake to wake the sleeper.
  class InterruptibleSleep
    def initialize
      @eventRead, @eventWrite = IO.pipe
      @eventPending = false
      @mutex = Mutex.new
    end

    # Sleep.
    def sleep(seconds)
      if IO.select([@eventRead], nil, nil, seconds)
        @eventRead.read(1)
      end
    end

    # Wake the sleeper.
    def wake
      @mutex.synchronize do
        @eventWrite.print "X" if ! @eventPending
      end
    end
  end
end
