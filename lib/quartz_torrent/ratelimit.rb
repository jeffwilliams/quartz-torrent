module QuartzTorrent

  # This class can be used to limit the rate at which work is done.
  class RateLimit
    # unitsPerSecond: Each second this many units are added to a pool. At any time
    #   up to the number of units in the pool may be withdrawn.
    # upperLimit: The maximum size of the pool. This controls how bursty the rate is. 
    #   For example, if the rate is 1/s and the limit is 5, then if there was no withdrawals
    #   for 5 seconds, then the max pool size is reached, and the next withdrawal may be 5, meaning
    #   5 units could be used instantaneously. However the average for the last 5 seconds is still 1/s.
    # initialValue: Initial size of the pool.
    def initialize(unitsPerSecond, upperLimit, initialValue)
      @unitsPerSecond = unitsPerSecond.to_f
      @upperLimit = upperLimit.to_f
      @initialValue = initialValue.to_f
      @pool = @initialValue
      @time = Time.new
    end
 
    # Return the limit in units per second
    attr_reader :unitsPerSecond

    # Set the limit in units per second.
    def unitsPerSecond=(v)
      @unitsPerSecond = v.to_f
    end

    # How much is in the pool.
    def avail
      updatePool
      @pool
    end

    # Withdraw this much from the pool.
    def withdraw(n)
      updatePool
      @pool -= n
    end

    private
    def updatePool
      now = Time.new
      @pool = @pool + (now - @time)*@unitsPerSecond
      @pool = @upperLimit if @pool > @upperLimit
      @time = now
    end
  end
end
