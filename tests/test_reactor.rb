#!/usr/bin/env ruby 
require 'rubygems'
require 'minitest/unit'
require 'minitest/autorun'
require 'socket'
require 'logger'
require 'fileutils'
require './src/reactor.rb'

TestDataDir = "tests/data"
TestDataTmpDir = "tests/data/tmp"

if ! File.directory?(TestDataTmpDir)
  FileUtils.mkdir TestDataTmpDir
end

class SimpleServer
  def start(port)
    socket = Socket.new( AF_INET, SOCK_STREAM, 0 )
    sockaddr = Socket.pack_sockaddr_in( port, "0.0.0.0" )
    socket.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
    socket.bind( sockaddr )
    puts "SimpleServer: listening on #{port}"
    socket.listen( 5 )

    client, clientAddr = socket.accept
    puts "SimpleServer: client connected"
     
    # Read 5 bytes
    @data = client.read(5)
    puts "SimpleServer: read 5 bytes"
    writeData(client)
    #client.write("hello")
    #puts "SimpleServer: sending 5 bytes"

    client.close
    socket.close
    puts "SimpleServer: exiting"
  end
  attr_accessor :data

  def writeData(client)
    client.write("hello")
    puts "SimpleServer: sending 5 bytes"
  end
end

class SimpleServer2 < SimpleServer
  def writeData(client)
    puts "SimpleServer: sending 1 bytes"
    client.write("h")
    client.flush
    sleep 0.2
    puts "SimpleServer: sending 2 bytes"
    client.write("el")
    client.flush
    sleep 0.2
    puts "SimpleServer: sending 2 bytes"
    client.write("lo")
    client.flush
  end
end

class SimpleServer3 < SimpleServer
  def writeData(client)
    # Write nothing so other end gets EOF
  end
end

class SimpleHandler < QuartzTorrent::Handler
  def initialize
    @readData = nil
    @connectErrorFlag = false
    @errorFlag = false
  end

  attr_accessor :readData
  attr_accessor :connectErrorFlag
  attr_accessor :errorFlag

  def connectError(metadata, details)
    puts "SimpleHandler: connect error: #{details}"
    @connectErrorFlag = true
    stopReactor
  end

  def clientInit(metadata)
    puts "SimpleHandler: clientInit called. Writing data"
    write("hello")
  end

  def serverInit(metadata, addr, port)
    puts "SimpleHandler: serverInit called: connection from #{addr}:#{port}. Reading 5 bytes"
    @readData = read(5)
    puts "SimpleHandler: writing 5 bytes"
    write("hello")
    stopReactor
  end

  def recvData(metadata)
    puts "SimpleHandler: reading 5 bytes"
    @readData = read(5)
    puts "SimpleHandler: done reading 5 bytes. Stopping reactor"
    stopReactor
  end

  def timerExpired(metadata)
  end

  def error(metadata, details)
    @errorFlag = true
    stopReactor
  end
end

class SimpleHandler2 < SimpleHandler
  def recvData(metadata)
    puts "SimpleHandler: reading 5 bytes"
    @readData = read(5)
    puts "SimpleHandler: done reading 5 bytes. "
    # Write some more data
    write("how are you?")
  end

  def serverInit(metadata, addr, port)
    puts "SimpleHandler: serverInit called: connection from #{addr}:#{port}. Reading 5 bytes"
    @readData = read(5)
    scheduleTimer(0,:closer,false, true)
    setMetaInfo(:conn)
  end

  def timerExpired(metainfo)
    begin
      if metainfo == :closer
        puts "SimpleHandler: closing connection in timer"
        io = findIoByMetainfo(:conn)
        if io
          close(io)
        end
        scheduleTimer(1,:finisher, false, false)
      else
        stopReactor
      end
    rescue
      puts "SimpleHandler2: Exception in timer handler: #{$!}"
      puts "#{$!.backtrace.join("\n")}"
      @errorFlag = true
      stopReactor
    end
  end
end

class SimpleClient
  def initialize
    @readData = nil
    @readError = nil
    @readEof = nil
  end

  attr_accessor :readData
  attr_accessor :readError
  attr_accessor :readEof

  def go(port, addr)
    socket = Socket.new(AF_INET, SOCK_STREAM, 0)
    addr = Socket.pack_sockaddr_in(port, addr)
    socket.connect(addr) 

    socket.write("hello")
    begin
      @readData = socket.read(5)
      @readEof = true if @readData.nil?
      puts "SimpleClient: read '#{@readData}' #{@readData.class}"
      socket.close
    rescue
      @readError = true
    end
  end
end

class SimpleFileHandler < QuartzTorrent::Handler
  def initialize
    @readData = nil
    @errorFlag = false
  end

  attr_accessor :readData
  attr_accessor :errorFlag

  def recvData(metadata)
    begin
      puts "SimpleFileHandler: reading 5 bytes"
      @readData = read(5)
      puts "SimpleFileHandler: done reading 5 bytes. Stopping reactor"
      stopReactor
    rescue
      puts "SimpleFileHandler: exception #{$!}"
    end
  end

  def timerExpired(metadata)
  end

  def error(metadata, details)
    @errorFlag = true
    puts "SimpleFileHandler: error: #{details}"
    stopReactor
  end
end

class SimpleFileHandler2 < QuartzTorrent::Handler
  def initialize
    @readData = nil
    @errorFlag = false
  end

  attr_accessor :readData
  attr_accessor :errorFlag

  def recvData(metadata)
    begin
      # File starts off with 'hello'.
      # Write 3 bytes at the current position as 'xxx'
      # Then read 2 bytes which should be 'lo'.
      # Finally write 3 more yyy bytes.
      # The write is buffered so will happen after the read, but should still
      # result in the contents of the file being 'xxxloyyy' 
      write("xxx")
      @readData = read(5)
      write("yyy")
      
      stopReactor
    rescue
      puts "SimpleFileHandler: exception #{$!}"
    end
  end

  def timerExpired(metadata)
  end

  def error(metadata, details)
    @errorFlag = true
    puts "SimpleFileHandler: error: #{details}"
    stopReactor
  end
end

class TestReactor < MiniTest::Unit::TestCase
  def setup
  end


  def testTimerManager
    handler = QuartzTorrent::TimerManager.new
    handler.add(5, "a", false) # Add a 5 second nonrecurring timer
    handler.add(2, "b", false) 
    handler.add(3, "c", false)  
  
    # Check ordering
    assert_equal "b", handler.next.metainfo
    assert_equal "c", handler.next.metainfo
    assert_equal "a", handler.next.metainfo
 
    handler.add(5, "a", true) # Add a 5 second recurring timer
    handler.add(2, "b", true) 
    handler.add(3, "c", true)  

    # Check that recurring timers... recur
    n = handler.peek
    assert_equal "b", n.metainfo
    sleep n.secondsUntilExpiry
    handler.next

    n = handler.peek
    assert_equal "c", n.metainfo
    sleep n.secondsUntilExpiry
    handler.next

    n = handler.peek
    assert_equal "b", n.metainfo
    sleep n.secondsUntilExpiry
    handler.next

    n = handler.peek
    assert_equal "a", n.metainfo
    sleep n.secondsUntilExpiry
    handler.next

    # At this point b and c occur simultaneously
    t1 = handler.next
    t2 = handler.next
    assert "b" == t1.metainfo && "c" == t2.metainfo || "c" == t1.metainfo && "b" == t2.metainfo
  end

  def test_client
    server = SimpleServer.new
    thread = Thread.new do
      puts "Server thread started"
      begin
        server.start(9999)
      rescue
        puts "Exception ins erver thread: #{$!}"
        puts $!.backtrace.join("\n")
      end
    end
    sleep 0.4

    handler = SimpleHandler.new

    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    # Uncomment the following line and omment the one after to debug the reactor.
    #reactor = QuartzTorrent::Reactor.new(handler, logger)
    reactor = QuartzTorrent::Reactor.new(handler)
    reactor.connect("localhost", 9999, :meta, 2)
    reactor.start    

    thread.join

    assert_equal "hello", server.data
    assert_equal "hello", handler.readData
  end

  def test_client_timeout
    handler = SimpleHandler.new

    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    # Uncomment the following line and omment the one after to debug the reactor.
    #reactor = QuartzTorrent::Reactor.new(handler, logger)
    reactor = QuartzTorrent::Reactor.new(handler)
    reactor.connect("localhost", 9999, :meta, 1)
    reactor.start

    assert_equal true, handler.connectErrorFlag
  end

  def test_client_partialread
    server = SimpleServer2.new
    thread = Thread.new do
      puts "Server thread started"
      begin
        server.start(9999)
      rescue
        puts "Exception ins erver thread: #{$!}"
        puts $!.backtrace.join("\n")
      end
    end
    sleep 0.4

    handler = SimpleHandler.new

    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    # Uncomment the following line and omment the one after to debug the reactor.
    #reactor = QuartzTorrent::Reactor.new(handler, logger)
    reactor = QuartzTorrent::Reactor.new(handler)
    reactor.connect("localhost", 9999, :meta, 2)
    reactor.start    

    thread.join

    assert_equal "hello", server.data
    assert_equal "hello", handler.readData
  end

  def test_client_readerror
    server = SimpleServer3.new
    thread = Thread.new do
      puts "Server thread started"
      begin
        server.start(9999)
      rescue
        puts "Exception ins erver thread: #{$!}"
        puts $!.backtrace.join("\n")
      end
    end
    sleep 0.4

    handler = SimpleHandler.new

    assert_equal false, handler.errorFlag

    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    # Uncomment the following line and omment the one after to debug the reactor.
    #reactor = QuartzTorrent::Reactor.new(handler, logger)
    reactor = QuartzTorrent::Reactor.new(handler)
    reactor.connect("localhost", 9999, :meta, 2)
    reactor.start    

    thread.join

    assert_equal true, handler.errorFlag
  end

  def test_client_writeerror
    # Seems like in Linux when the remote peer disconnects
    # the socket gets flagged as ready for reading. Since the reactor
    # processes reads before writes, there's no way to easily test
    # a write after an EOF. This test ends up testing the read case again.

    server = SimpleServer.new
    thread = Thread.new do
      puts "Server thread started"
      begin
        server.start(9999)
      rescue
        puts "Exception ins erver thread: #{$!}"
        puts $!.backtrace.join("\n")
      end
    end
    sleep 0.4

    handler = SimpleHandler2.new

    assert_equal false, handler.errorFlag

    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG
    # Uncomment the following line and omment the one after to debug the reactor.
    #reactor = QuartzTorrent::Reactor.new(handler, logger)
    reactor = QuartzTorrent::Reactor.new(handler)
    reactor.connect("localhost", 9999, :meta, 2)
    reactor.start    

    thread.join

    assert_equal true, handler.errorFlag
  end

  def test_server
    # Test a server reactor.
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG

    handler = SimpleHandler.new


    # Uncomment the following line and omment the one after to debug the reactor.
    #reactor = QuartzTorrent::Reactor.new(handler, logger)
    reactor = QuartzTorrent::Reactor.new(handler)
    reactor.listen("0,0,0,0",9999,nil)

    client = nil
    thread = Thread.new do
      puts "Client thread started"
      begin
        client = SimpleClient.new
        client.go(9999,"localhost")
      rescue
        puts "Exception in client thread: #{$!}"
        puts $!.backtrace.join("\n")
      end
    end
    sleep 0.4
  
    reactor.start
    thread.join

    assert_equal "hello", client.readData
    assert_equal "hello", handler.readData

  end

  def test_server_close_from_timer 
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG

    # This handler will accept a client connection, read 5 bytes, close the client
    # connection, wait 1 second, then stop the reactor.
    handler = SimpleHandler2.new


    # Uncomment the following line and omment the one after to debug the reactor.
    #reactor = QuartzTorrent::Reactor.new(handler, logger)
    reactor = QuartzTorrent::Reactor.new(handler)
    reactor.listen("0,0,0,0",9999,nil)

    client = nil
    thread = Thread.new do
      puts "Client thread started"
      begin
        client = SimpleClient.new
        client.go(9999,"localhost")
      rescue
        puts "Exception in client thread: #{$!}"
        puts $!.backtrace.join("\n")
      end
    end
    sleep 0.4
  
    reactor.start
    thread.join

    # Client will have tried to read 5 bytes, but read will return nil instead since the 
    # server closed the connection causing an EOF.
    assert_equal true, client.readEof
    assert_equal false, handler.errorFlag
    assert_equal "hello", handler.readData

  end

  def test_fileio
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG

    handler = SimpleFileHandler.new

    fileName = TestDataDir + File::SEPARATOR + "tmpfile"
    File.open(fileName,"w") do |file|
      file.write "hello"
    end

    # Uncomment the following line and omment the one after to debug the reactor.
    reactor = QuartzTorrent::Reactor.new(handler, logger)
    #reactor = QuartzTorrent::Reactor.new(handler)

    reactor.open(fileName,"r+", :file)
    
    reactor.start
    assert_equal "hello", handler.readData
  end

  def test_seek
    logger = Logger.new(STDOUT)
    logger.level = Logger::DEBUG

    handler = SimpleFileHandler2.new

    fileName = TestDataTmpDir + File::SEPARATOR + "tmpfile"
    File.open(fileName,"w") do |file|
      file.write "hello"
    end

    # Uncomment the following line and omment the one after to debug the reactor.
    reactor = QuartzTorrent::Reactor.new(handler, logger)
    #reactor = QuartzTorrent::Reactor.new(handler)

    reactor.open(fileName,"r+", :file)
    
    reactor.start
    assert_equal "hello", handler.readData
    assert_equal "xxxloyyy", File.open(fileName,"r").read
  end

  # TODO:
  # - test passing invalid data to connect or listen: does error get called?


end

