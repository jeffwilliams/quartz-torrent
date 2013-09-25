class Hash
  # Treat the array as a hash of lists. This method will append 'value' to the list
  # at key 'key' in the hash. If there is no list for 'key', one is created.
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
  # This is Linux specific: system call number for gettid
  SYSCALL_GETTID = 224

  def self.bytesToHex(v, addSpaces = nil)
    s = ""
    v.each_byte{ |b|
      hex = b.to_s(16)
      hex = "0" + hex if hex.length == 1
      s << hex
      s << " " if addSpaces == :add_spaces
    }
    s
  end

  def self.arrayShuffleRange!(array, start, length)
    raise "Invalid range" if start + length > array.size

    (start+length).downto(start+1) do |i|
      r = start + rand(i-start)
      array[r], array[i-1] = array[i-1], array[r]
    end
    true
  end

  def self.logBacktraces
    logger = LogManager.getLogger("util")

    Thread.list.each do |thread|
      lwpid = ""
      if thread[:lwpid]
        lwpid = " [lwpid #{thread[:lwpid]}]"
      end

      logger.error "Thread #{thread[:name]} #{thread.object_id}#{lwpid}: #{thread.status}\n" + thread.backtrace.join("\n")
    end
  end

  # Method to set a few thread-local variables useful in debugging. Threads should call this when started.
  def self.initThread(name)
    Thread.current[:name] = name
    isLinux = RUBY_PLATFORM.downcase.include?("linux")
    Thread.current[:lwpid] = syscall(SYSCALL_GETTID) if isLinux
  end

end

