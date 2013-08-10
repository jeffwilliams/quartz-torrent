module QuartzTorrent
  class Rate
    class Sample
      def initialize(value)
        @value = value
        @time = Time.new
      end
      attr_accessor :value
      attr_accessor :time
    end

    def initialize(window = 8)
      reset
      @window = window
      @maxSamples = 100
    end

    def value
      now = Time.new
      # Age out old samples.
      @samples = @samples.drop_while{ |s| now - s.time > @window  }
      return 0 if @samples.size < 2
      @samples.last(@samples.size-1).reduce(0){ |memo, s| memo + s.value }.to_f / (now - @samples.first.time)
    end

    def update(sample)
      @samples.push Sample.new(sample)
      @samples.shift if @samples.size >= @maxSamples
    end

    def reset
      @samples = []
    end
  end
end
