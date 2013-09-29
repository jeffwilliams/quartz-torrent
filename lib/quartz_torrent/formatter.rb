module QuartzTorrent
  # Class that can be used to format different quantities into 
  # human readable strings.
  class Formatter
    Kb = 1024
    Meg = 1024*Kb
    Gig = 1024*Meg

    # Format a size in bytes.
    def self.formatSize(size)
      s = size.to_f
      if s >= Gig
        s = "%.2fGB" % (s / Gig)
      elsif s >= Meg
        s = "%.2fMB" % (s / Meg)
      elsif s >= Kb
        s = "%.2fKB" % (s / Kb)
      else
        s = "%.2fB" % s
      end
      s
    end

    # Format a floating point number as a percentage with one decimal place.
    def self.formatPercent(frac)
      s = "%.1f" % (frac.to_f*100)
      s + "%"
    end
    
    # Format a speed in bytes per second.
    def self.formatSpeed(s)
      Formatter.formatSize(s) + "/s"
    end

    # Format a duration of time in seconds.
    def self.formatTime(secs)
      s = ""
      time = secs.to_i
      arr = []
      conv = [60,60]
      unit = ["s","m","h"]
      conv.each{ |c|
        v = time % c
        time = time / c
        arr.push v
      }
      arr.push time
      i = unit.size-1
      arr.reverse.each{ |v|
        if v == 0
          i -= 1
        else
          break
        end
      }
      while i >= 0
        s << arr[i].to_s + unit[i]
        i -= 1
      end
      
      s = "0s" if s.length == 0
 
      s
    end

    # Parse a size in the format '50 KB'
    def self.parseSize(size)
      if size =~ /(\d+(?:\.\d+)?)\s*([^\d]+)*/
        value = $1.to_f
        suffix = ($2 ? $2.downcase : nil)

        multiplicand = 1
        if suffix.nil? || suffix[0] == 'b'
          multiplicand = 1
        elsif suffix[0,2] == 'kb'
          multiplicand = Kb
        elsif suffix[0,2] == 'mb'
          multiplicand = Meg
        elsif suffix[0,2] == 'gb'
          multiplicand = Gig
        else
          raise "Unknown suffix '#{suffix}' for size '#{size}'"
        end
   
        value*multiplicand
      else  
        raise "Malformed size '#{size}'"
      end
    end
  end

end
