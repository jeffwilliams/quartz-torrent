class Array
  # Perform a binary search for a value in the array between the index low and high. This method expects a block. The
  # block is passed a value v, and should return true if the target value is >= v, and false otherwise.
  def binsearch(low = nil, high = nil) 
    return nil if length == 0
    result = binsearch_index(low, high){ |x| yield x if !x.nil?}
    result = at(result) if result
    result
  end

  # Perform a binary search for an index in the array between the index low and high. This method expects a block. The
  # block is passed a value v, and should return true if the target value is >= v, and false otherwise.
  def binsearch_index(low = nil, high = nil) 
    return nil if length == 0
    low = 0 if !low
    high = length if !high

    if low == high
      if yield at(low)
        return low
      else
        return nil
      end
    end

    mid = (high-low)/2 + low
    if yield at(mid)
      # this value >= target.
      result = binsearch_index(low, mid == low ? mid : mid-1){ |x| yield x if !x.nil?}
      if result
        return result
      else
        return mid
      end
    else
      # this value < target
      binsearch_index(mid == high ? mid : mid+1, high){ |x| yield x if !x.nil?}
    end
  end
end

module QuartzTorrent
  # This class is used to map consecutive integer regions to objects. The lowest end of the 
  # lowest region is assumed to be 0.
  class RegionMap
    def initialize
      @map = []
      @sorted = false
    end

    # Add a region that ends at the specified 'regionEnd' with the associated 'obj'
    def add(regionEnd, obj)
      @map.push [regionEnd, obj]
      @sorted = false
    end

    # Given an integer value, find which region it falls in and return the object associated with that region.
    def findValue(value)
      if ! @sorted
        @map.sort{ |a,b| a[0] <=> b[0] }
        @sorted = true
      end
      
      @map.binsearch{|x| x[0] >= value}[1]
    end

    def findIndex(value)
      if ! @sorted
        @map.sort{ |a,b| a[0] <=> b[0] }
        @sorted = true
      end
      
      @map.binsearch_index{|x| x[0] >= value}
    end

    # Given a value, return a list of the form [index, value, left, right, offset] where
    # index is the zero-based index in this map of the region, value is the associated object, 
    # left is the lowest value in the region, right is the highest, and offset is the
    # offset within the region of the value.
    def find(value)
      
      index = findIndex(value)
      return nil if ! index
      result = at(index)

      if index == 0
        offset = value
      else
        offset = value - result[1]
      end
      
      [index, result[0], result[1], result[2], offset]
    end

    # For the region with index i, return an array of the form [value, left, right]
    def at(i)
      return nil if @map.length == 0
      if i == 0
        left = 0
      else
        left = @map[i-1][0]+1
      end

      [@map[i][1],left,@map[i][0]]
    end

    def [](i)
      at(i)
    end
 
    # Return the rightmost index of the final region, or -1 if no regions have been added.
    def maxIndex
      @map.size-1
    end

    # For the final region, return an array of the form [index, value, left, right]
    def last
      return nil if ! @map.last
      if @map.length == 1
        left = 0
      else
        left = @map[@map.length-2][0]+1
      end
      [@map.length-1,@map.last[1],left,@map.last[0]]
    end

  end
end
