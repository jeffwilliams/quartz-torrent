module QuartzTorrent
  # Class that can be used to format different quantities into 
  # human readable strings.
  class Formatter
    Kb = 1024
    Meg = 1024*Kb
    Gig = 1024*Meg

    def self.formatSize(size)
      s = size.to_f
      if s > Gig
        s = "%.2fGB" % (s / Gig)
      elsif s > Meg
        s = "%.2fMB" % (s / Meg)
      elsif s > Kb
        s = "%.2fKB" % (s / Kb)
      else
        s = "%.2fB" % s
      end
      s
    end

    def self.formatPercent(frac)
      s = "%.1f" % (frac.to_f*100)
      s + "%"
    end
    
    def self.formatSpeed(s)
      Formatter.formatSize(s) + "/s"
    end

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
      s
    end
  end
end
