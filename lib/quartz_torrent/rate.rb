module QuartzTorrent
  # Class that keeps track of a rate, for example a download or upload rate.
  # The class is used by calling 'update' with samples (numbers) representing 
  # the amount of units being measured accrued since the last call, and value
  # returns the rate in units/second.
  #
  # This is implemented as an exponential moving average. The weight of the 
  # current sample is based on an exponention function of the time since the 
  # last sample. To reduce CPU usage, when update is called with a new sample
  # the new average is not calculated immediately, but instead the samples are
  # summed until 1 second has elapsed before recalculating the average.
  class Rate
    # Create a new Rate that measures the rate using samples.
    # avgPeriod specifies the duration over which the samples are averaged.
    def initialize(avgPeriod = 4.0)
      reset
      @avgPeriod = avgPeriod.to_f
    end

    # Get the current rate. If there are too few samples, 0 is returned.
    def value
      @value ? @value : 0.0
    end

    # Update the rate by passing another sample (number) representing units accrued since the last
    # call to update.
    def update(sample)
      now = Time.new
      elapsed = now - @time
      @sum += sample
      if elapsed > 1.0
        @value = newValue elapsed, @sum/elapsed
        @time = now
        @sum = 0.0
      end
    end

    # Reset the rate to empty.
    def reset
      @value = nil
      @time = Time.new
      @sum = 0.0
    end

    private
    def newValue(elapsed, sample)
      return sample if ! @value
      a = alpha elapsed
      a*sample + (1-a)*@value
    end

    # See http://en.wikipedia.org/wiki/Moving_average#Application_to_measuring_computer_performance
    def alpha(elapsed)
      1 - Math.exp(-elapsed/@avgPeriod)
    end
  end
end
