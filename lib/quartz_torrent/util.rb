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

  def self.hexToBytes(v)
    [v].pack "H*"
  end

  def self.arrayShuffleRange!(array, start, length)
    raise "Invalid range" if start + length > array.size

    (start+length).downto(start+1) do |i|
      r = start + rand(i-start)
      array[r], array[i-1] = array[i-1], array[r]
    end
    true
  end

  def self.logBacktraces(io)
    logger = nil
    logger = LogManager.getLogger("util") if ! io
    isLinux = RUBY_PLATFORM.downcase.include?("linux")

    Thread.list.each do |thread|
      lwpid = ""

      Thread.current[:lwpid] = syscall(SYSCALL_GETTID) if ! thread[:lwpid] && isLinux
      lwpid = " [lwpid #{thread[:lwpid]}]" if thread[:lwpid]

      msg = "Thread #{thread[:name]} #{thread.object_id}#{lwpid}: #{thread.status}\n  " + thread.backtrace.join("\n  ")
      if io
        io.puts msg
      else
        logger.error msg
      end
    end
  end

  # Method to set a few thread-local variables useful in debugging. Threads should call this when started.
  def self.initThread(name)
    Thread.current[:name] = name
  end

end

