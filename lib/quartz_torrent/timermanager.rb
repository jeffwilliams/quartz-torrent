require 'pqueue'

module QuartzTorrent
  # Class used to manage timers.
  class TimerManager
    class TimerInfo
      def initialize(duration, recurring, metainfo)
        @duration = duration
        @recurring = recurring
        @metainfo = metainfo
        @cancelled = false
        refresh
      end
      attr_accessor :recurring
      attr_accessor :duration
      attr_accessor :expiry
      attr_accessor :metainfo
      # Since pqueue doesn't allow removal of anything but the head
      # we flag deleted items so they are deleted when they are pulled
      attr_accessor :cancelled

      def secondsUntilExpiry
        @expiry - Time.new
      end

      def refresh
        @expiry = Time.new + @duration
      end
    end

    def initialize(logger = nil)
      @queue = PQueue.new { |a,b| b.expiry <=> a.expiry }
      @mutex = Mutex.new
      @logger = logger
    end

    # Add a timer. Parameter 'duration' specifies the timer duration in seconds,
    # 'metainfo' is caller information passed to the handler when the timer expires,
    # 'recurring' should be true if the timer will repeat, or false if it will only
    # expire once, and 'immed' when true specifies that the timer should expire immediately 
    # (and again each duration if recurring) while false specifies that the timer will only
    # expire the first time after it's duration elapses.
    def add(duration, metainfo = nil, recurring = true, immed = false)
      raise "TimerManager.add: Timer duration may not be nil" if duration.nil?
      info = TimerInfo.new(duration, recurring, metainfo)
      info.expiry = Time.new if immed
      @mutex.synchronize{ @queue.push info }
      info
    end
  
    # For testing. Add a cancelled timer.
    def add_cancelled(duration, metainfo = nil, recurring = true, immed = false)
      raise "TimerManager.add: Timer duration may not be nil" if duration.nil?
      info = TimerInfo.new(duration, recurring, metainfo)
      info.expiry = Time.new if immed
      info.cancelled = true
      @mutex.synchronize{ @queue.push info }
      info
    end

    # Cancel a timer.
    def cancel(timerInfo)
      timerInfo.cancelled = true
    end

    # Return the next timer event from the queue, but don't remove it from the queue.
    def peek
      result = nil
      @mutex.synchronize do 
        clearCancelled
        result = @queue.top 
      end
      result
    end

    # Remove the next timer event from the queue and return it as a TimerHandler::TimerInfo object.
    # Warning: if the timer is a recurring timer, the secondsUntilExpiry will be set to the NEXT time
    # the timer would expire, instead of this time. If the original secondsUntilExpiry is needed, 
    # pass a block to this method, and the block will be called with the original secondsUntilExpiry.
    def next
      result = nil
      @mutex.synchronize do 
        clearCancelled
        result = @queue.pop 
      end
      if result
        yield result.secondsUntilExpiry if block_given?
        if result.recurring
          result.refresh
          @mutex.synchronize{ @queue.push result }
        end
      end
      result
    end

    def to_s
      arr = nil
      @mutex.synchronize do
        arr = @queue.to_a
      end
      s = "now = #{Time.new}. Queue = ["
      arr.each do |e|
        s << "(#{e.object_id};#{e.expiry};#{e.metainfo[0]};#{e.secondsUntilExpiry}),"
      end
      s << "]"
    end

    def empty?
      @queue.empty?
    end

    private 
    
    def clearCancelled
      while @queue.top && @queue.top.cancelled
        @queue.pop 
      end
    end
  end
end
