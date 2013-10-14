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

  # Return a hex string representing the bytes in the passed string.
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

  # Given a hex string representing a sequence of bytes, convert it the the original bytes. Inverse of bytesToHex. 
  def self.hexToBytes(v)
    [v].pack "H*"
  end

  # Shuffle the subset of elements in the given array between start and start+length-1 inclusive.
  def self.arrayShuffleRange!(array, start, length)
    raise "Invalid range" if start + length > array.size

    (start+length).downto(start+1) do |i|
      r = start + rand(i-start)
      array[r], array[i-1] = array[i-1], array[r]
    end
    true
  end

  # Store Linux Lightweight process ids (LWPID) on each thread.
  # If this is called a while before logBacktraces the backtraces will
  # include lwpids.
  def self.setThreadLwpid(thread = nil)
    # This function works by calling the GETTID system call in Linux. That
    # system call must be called in the thread that we want to get the lwpid of,
    # but the user may not have created those threads and so can't call the system call
    # in those threads (think Sinatra). To get around this this function runs code in the
    # thread by adding a trace function to the thread, and on the first traced operation
    # stores the LWPID on the thread and unregisters itself.    

    isLinux = RUBY_PLATFORM.downcase.include?("linux")
    return if !isLinux

    tracer = Proc.new do
      Thread.current[:lwpid] = syscall(SYSCALL_GETTID) if ! Thread.current[:lwpid] && isLinux
      Thread.current.set_trace_func(nil)
    end
    
    if thread
      thread.set_trace_func(tracer)
    else
      Thread.list.each { |thread| thread.set_trace_func(tracer) }
    end
  end

  # Log backtraces of all threads currently running. The threads are logged to the 
  # passed io, or if that's nil they are written to the logger named 'util' at error level.
  def self.logBacktraces(io)
    logger = nil
    logger = LogManager.getLogger("util") if ! io
    isLinux = RUBY_PLATFORM.downcase.include?("linux")

    Thread.list.each do |thread|
      lwpid = ""

      setThreadLwpid thread if ! thread[:lwpid] && isLinux
      lwpid = " [lwpid #{thread[:lwpid]}]" if thread[:lwpid]

      msg = "Thread #{thread[:name]} #{thread.object_id}#{lwpid}: #{thread.status}\n  " + (thread.backtrace ? thread.backtrace.join("\n  ") : "no backtrace")
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

