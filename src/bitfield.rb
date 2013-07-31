module QuartzTorrent
  # A bitfield that allows querying and setting individual bits, as well as serializing and unserializing.
  class Bitfield
    # Create a bitfield of length 'length' in bits.
    def initialize(length)
      @length = length
      if @length == 0
        @data = Array.new(0)
      else
        @data = Array.new((length-1)/8+1, 0)
      end
    end

    attr_reader :length
    def byteLength
      @data.length
    end

    def set(bit)
      quotient = bit >> 3
      remainder = bit & 0x7
      mask = 0x80 >> remainder

      raise "Bit #{bit} out of range of bitfield with length #{length}" if quotient >= @data.length
      @data[quotient] |= mask
    end  

    def clear(bit)
      quotient = bit >> 3
      remainder = bit & 0x7
      mask = ~(0x80 >> remainder)
      
      raise "Bit #{bit} out of range of bitfield with length #{length}" if quotient >= @data.length
      @data[quotient] &= mask
    end  
    
    # Returns true if the bit is set, false otherwise.
    def set?(bit)
      quotient = bit >> 3
      remainder = bit & 0x7
      mask = 0x80 >> remainder
    
      raise "Bit #{bit} out of range of bitfield with length #{length}" if quotient >= @data.length
      @data[quotient] & mask > 0
    end

    # Are all bits in the Bitfield set?
    def allSet?
      # Check all but last byte quickly
      (@data.length-1).times do |i|
        return false if @data[i] & 0xff != 0xff
      end
      # Check last byte slowly
      toCheck = @length % 8
      toCheck = 8 if toCheck == 0
      ((@length-toCheck)..(@length-1)).each do |i|
        return false if ! set?(i)
      end
      true
    end

    def setAll
      @data.fill(0xff)
    end

    def clearAll
      @data.fill(0x00)
    end

    def union(bitfield)
      raise "That's not a bitfield" if ! bitfield.is_a?(Bitfield)
      raise "bitfield lengths must be equal" if ! bitfield.length == length
    
      result = Bitfield.new(length)
      (@data.length).times do |i|
        result.data[i] = @data[i] | bitfield.data[i]
      end
      result
    end

    def copyFrom(bitfield)
      raise "Source bitfield is too small (#{bitfield.length} < #{length})" if bitfield.length < length
      (@data.length).times do |i|
        @data[i] = bitfield.data[i]
      end
    end

    def compliment!
      @data.collect!{ |e| ~e }
      self
    end

    def serialize
      @data.pack "C*"
    end

    def unserialize(s)
      @data = s.unpack "C*"
    end

    def to_s(groupsOf = 8)
      groupsOf = 8 if groupsOf == 0
      s = ""
      length.times do |i|
        s << (set?(i) ? "1" : "0")
        s << " " if i % groupsOf == 0
      end
      s
    end

    # Count the number of bits that are set. Slow: could use lookup table.
    def countSet
      count = 0
      length.times do |i|
        count += 1 if set?(i)
      end
      count
    end

    protected
    def data
      @data
    end
  end
end
