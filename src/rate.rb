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

    def initialize(window = 30)
      reset
      @window = window
    end

    def value
      now = Time.new
      # Age out old samples.
      @samples.delete_if{ |s| now - s.time > @window }
      return nil if @samples.empty?
      @samples.reduce(0){ |memo, s| memo + s.value } / (@samples.last.time - @samples.first.time)
    end

    def update(sample)
      @samples.push Sample.new(sample)
    end

    def reset
      @samples = []
    end
  end
end
