require 'thread'

module QuartzTorrent
  class InterruptibleSleep
    def initialize
      @eventRead, @eventWrite = IO.pipe
      @eventPending = false
      @mutex = Mutex.new
    end

    def sleep(seconds)
      if IO.select([@eventRead], nil, nil, seconds)
        @eventRead.read(1)
      end
    end

    def wake
      @mutex.synchronize do
        @eventWrite.print "X" if ! @eventPending
      end
    end
  end
end
