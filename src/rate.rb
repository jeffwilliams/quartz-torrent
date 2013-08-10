module QuartzTorrent
  # Class that keeps track of a rate, for example a download or upload rate.
  # The class is used by calling 'update' with samples (numbers) representing 
  # the amount of units being measured accrued since the last call, and value
  # returns the rate in units/second.
  class Rate
    # A sample taken at a certain time. Used to measure rate.
    class Sample
      def initialize(value)
        @value = value
        @time = Time.new
      end
      # Value of the sample
      attr_accessor :value
      # Time when the sample was taken
      attr_accessor :time
    end

    # Create a new Rate that measures the rate using samples from the last 'window' seconds.
    def initialize(window = 8)
      reset
      @window = window
      @maxSamples = 100
    end

    # Get the current rate. If there are too few samples, 0 is returned.
    def value
      now = Time.new
      # Age out old samples.
      @samples = @samples.drop_while{ |s| now - s.time > @window  }
      return 0 if @samples.size < 2
      @samples.last(@samples.size-1).reduce(0){ |memo, s| memo + s.value }.to_f / (now - @samples.first.time)
    end

    # Update the rate by passing another sample (number) representing units accrued since the last
    # call to update.
    def update(sample)
      @samples.push Sample.new(sample)
      @samples.shift if @samples.size >= @maxSamples
    end

    # Reset the rate to empty.
    def reset
      @samples = []
    end
  end
end
