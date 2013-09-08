module QuartzTorrent

  # A bitfield that allows querying and setting individual bits, as well as serializing and unserializing.
  class Bitfield
=begin
    # Code used to generate lookup table:
print "["
256.times do |i|
  # count bits set
  o = i
  c = 0
  8.times do
    c += 1 if i & 1 > 0
    i >>= 1
  end

  print "," if o > 0
  puts if o > 0 && o % 20 == 0
  print "#{c}"
end
puts "]"

=end

    # Lookup table. The value at index i is the number of bits on in byte with value i.
    @@bitsSetInByteLookup = 
      [0,1,1,2,1,2,2,3,1,2,2,3,2,3,3,4,1,2,2,3,
      2,3,3,4,2,3,3,4,3,4,4,5,1,2,2,3,2,3,3,4,
      2,3,3,4,3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,
      4,5,5,6,1,2,2,3,2,3,3,4,2,3,3,4,3,4,4,5,
      2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,2,3,3,4,
      3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,
      4,5,5,6,5,6,6,7,1,2,2,3,2,3,3,4,2,3,3,4,
      3,4,4,5,2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,
      2,3,3,4,3,4,4,5,3,4,4,5,4,5,5,6,3,4,4,5,
      4,5,5,6,4,5,5,6,5,6,6,7,2,3,3,4,3,4,4,5,
      3,4,4,5,4,5,5,6,3,4,4,5,4,5,5,6,4,5,5,6,
      5,6,6,7,3,4,4,5,4,5,5,6,4,5,5,6,5,6,6,7,
      4,5,5,6,5,6,6,7,5,6,6,7,6,7,7,8]


    # Create a bitfield of length 'length' in bits.
    def initialize(length)
      @length = length
      if @length == 0
        @data = Array.new(0)
      else
        @data = Array.new((length-1)/8+1, 0)
      end
    end

    # Length of the Bitfield in bits.
    attr_reader :length

    
    # Length of the Bitfield in bytes.
    def byteLength
      @data.length
    end

    # Set the bit at index 'bit' to 1.
    def set(bit)
      quotient = bit >> 3
      remainder = bit & 0x7
      mask = 0x80 >> remainder

      raise "Bit #{bit} out of range of bitfield with length #{length}" if quotient >= @data.length
      @data[quotient] |= mask
    end  

    # Clear the bit at index 'bit' to 0.
    def clear(bit)
      quotient = bit >> 3
      remainder = bit & 0x7
      mask = ~(0x80 >> remainder)
      
      raise "Bit #{bit} out of range of bitfield with length #{length}" if quotient >= @data.length
      @data[quotient] &= mask
    end  
    
    # Returns true if the bit is set, false otherwise.
    def set?(bit)
      #raise "Bit #{bit} out of range of bitfield with length #{length}" if quotient >= @data.length
      (@data[bit >> 3] << (bit & 0x7)) & 0x80 > 0
    end

    # Are all bits in the Bitfield set?
    def allSet?
      # Check all but last byte quickly
      (@data.length-1).times do |i|
        return false if @data[i] != 0xff
      end
      # Check last byte slowly
      toCheck = @length % 8
      toCheck = 8 if toCheck == 0
      ((@length-toCheck)..(@length-1)).each do |i|
        return false if ! set?(i)
      end
      true
    end

    # Are all bits in the Bitfield clear?
    def allClear?
      # Check all but last byte quickly
      (@data.length-1).times do |i|
        return false if @data[i] != 0
      end
      # Check last byte slowly
      toCheck = @length % 8
      toCheck = 8 if toCheck == 0
      ((@length-toCheck)..(@length-1)).each do |i|
        return false if set?(i)
      end
      true
    end

    # Set all bits in the field to 1.
    def setAll
      @data.fill(0xff)
    end

    # Clear all bits in the field to 0.
    def clearAll
      @data.fill(0x00)
    end

    # Calculate the union of this bitfield and the passed bitfield, and 
    # return the result as a new bitfield. 
    def union(bitfield)
      raise "That's not a bitfield" if ! bitfield.is_a?(Bitfield)
      raise "bitfield lengths must be equal" if ! bitfield.length == length
    
      result = Bitfield.new(length)
      (@data.length).times do |i|
        result.data[i] = @data[i] | bitfield.data[i]
      end
      result
    end

    # Calculate the intersection of this bitfield and the passed bitfield, and 
    # return the result as a new bitfield. 
    def intersection(bitfield)
      raise "That's not a bitfield" if ! bitfield.is_a?(Bitfield)
      raise "bitfield lengths must be equal" if ! bitfield.length == length

      newbitfield = Bitfield.new(length)
      newbitfield.copyFrom(self)
      newbitfield.intersection!(bitfield)
    end

    # Update this bitfield to be the intersection of this bitfield and the passed bitfield.
    def intersection!(bitfield)
      raise "That's not a bitfield" if ! bitfield.is_a?(Bitfield)
      raise "bitfield lengths must be equal" if ! bitfield.length == length
        
      (@data.length).times do |i|
        @data[i] = @data[i] & bitfield.data[i]
      end
      self
    end

    # Set the contents of this bitfield to be the same as the passed bitfield. An exception is 
    # thrown if the passed bitfield is smaller than this.
    def copyFrom(bitfield)
      raise "Source bitfield is too small (#{bitfield.length} < #{length})" if bitfield.length < length
      (@data.length).times do |i|
        @data[i] = bitfield.data[i]
      end
    end

    # Calculate the compliment of this bitfield, and 
    # return the result as a new bitfield. 
    def compliment
      bitfield = Bitfield.new(length)
      bitfield.copyFrom(self)
      bitfield.compliment!
    end

    # Update this bitfield to be the compliment of itself.
    def compliment!
      @data.collect!{ |e| ~e }
      self
    end

    # Serialize this bitfield as a string.
    def serialize
      @data.pack "C*"
    end

    # Unserialize this bitfield from a string.
    def unserialize(s)
      @data = s.unpack "C*"
    end

    # Return a display string representing the bitfield.
    def to_s(groupsOf = 8)
      groupsOf = 8 if groupsOf == 0
      s = ""
      length.times do |i|
        s << (set?(i) ? "1" : "0")
        s << " " if i % groupsOf == 0
      end
      s
    end

    # Count the number of bits that are set. 
    def countSet
      @data.reduce(0){ |memo, v| memo + @@bitsSetInByteLookup[v] }
    end

    protected
    def data
      @data
    end
  end

  # A bitfield that is always empty.
  class EmptyBitfield < Bitfield
    def initialize
      @length = 0
    end

    # Length of the Bitfield in bits.
    attr_reader :length

    # Length of the Bitfield in bytes.
    def byteLength
      0
    end

    # Set the bit at index 'bit' to 1.
    def set(bit)
    end  

    # Clear the bit at index 'bit' to 0.
    def clear(bit)
    end  
    
    # Returns true if the bit is set, false otherwise.
    def set?(bit)
      false
    end

    # Are all bits in the Bitfield set?
    def allSet?
      false
    end

    # Are all bits in the Bitfield clear?
    def allClear?
      true
    end

    # Set all bits in the field to 1.
    def setAll
    end

    # Clear all bits in the field to 0.
    def clearAll
    end

    # Calculate the union of this bitfield and the passed bitfield, and 
    # return the result as a new bitfield. 
    def union(bitfield)
      self
    end

    # Calculate the intersection of this bitfield and the passed bitfield, and 
    # return the result as a new bitfield. 
    def intersection(bitfield)
      self
    end

    # Update this bitfield to be the intersection of this bitfield and the passed bitfield.
    def intersection!(bitfield)
      self
    end

    # Set the contents of this bitfield to be the same as the passed bitfield. An exception is 
    # thrown if the passed bitfield is smaller than this.
    def copyFrom(bitfield)
    end

    # Calculate the compliment of this bitfield, and 
    # return the result as a new bitfield. 
    def compliment
      self
    end

    # Update this bitfield to be the compliment of itself.
    def compliment!
      self
    end

    # Serialize this bitfield as a string.
    def serialize
      ""
    end

    # Unserialize this bitfield from a string.
    def unserialize(s)
    end

    # Return a display string representing the bitfield.
    def to_s(groupsOf = 8)
      "empty"
    end

    # Count the number of bits that are set. Slow: could use lookup table.
    def countSet
      0
    end
  end
end
