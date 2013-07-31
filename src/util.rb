class Hash
  def pushToList(key, value)
    list = self[key]
    if ! list
      list = [] 
      self[key] = list
    end
    list.push value
  end
end

module QuartzTorrent
  def bytesToHex(v)
    s = ""
    v.each_byte{ |b|
      hex = b.to_s(16)
      hex = "0" + hex if hex.length == 1
      s << hex
      s << " "
    }
    s
  end

  def arrayShuffleRange!(array, start, length)
    raise "Invalid range" if start + length > array.size

    (start+length).downto(start+1) do |i|
      r = start + rand(i-start)
      array[r], array[i-1] = array[i-1], array[r]
    end
    true
  end
end

