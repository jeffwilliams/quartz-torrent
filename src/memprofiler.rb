module QuartzTorrent

  class MemProfiler
    def initialize
      @classes = []
    end

    # Add a class to the list of classes we count the living instances of.
    def trackClass(clazz)
      @classes.push clazz
    end

    # Return a hashtable keyed by class where the value is the number of that class of object still alive.
    def getCounts
      result = {}
      @classes.each do |c|
        count = 0
        ObjectSpace.each_object(c){ count += 1 }
        result[c] = count
      end
      result
    end
  end

end
