module QuartzTorrent

  # Utility class used for debugging memory leaks. It can be used to count the number of reachable
  # instances of selected classes.
  class MemProfiler
    def initialize
      @classes = []
    end

    # Add a class to the list of classes we count the reachable instances of.
    def trackClass(clazz)
      @classes.push clazz
    end

    # Return a hashtable keyed by class where the value is the number of that class of object still reachable.
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
