#!/usr/bin/env ruby
require 'fileutils'
require 'getoptlong'
require "ncurses"
require 'quartz_torrent'
require 'quartz_torrent/memprofiler'
require 'quartz_torrent/formatter'
require 'quartz_torrent/magnet'

# Set this to true to profile using ruby-prof.
$doProfiling = false

require 'ruby-prof' if $doProfiling

include QuartzTorrent

DebugTty = "/dev/pts/8"

$log = nil
begin
  $log = File.open DebugTty, "w"
rescue
  $log = $stdout
end


def getmaxyx(win)
  y = []
  x = []
  Ncurses::getmaxyx win, y, x
  [y.first,x.first]
end

def getyx(win)
  y = []
  x = []
  Ncurses.getyx win, y, x
  [y.first,x.first]
end

# Write string to window without allowing wrapping if the string is longer than available space.
def waddstrnw(win, str)
  maxy, maxx = getmaxyx(win)
  y,x = getyx(win)
 
  trunc = str[0,maxx-x]

  # If the string ended in a newline, make the truncated string also end in a newline
  trunc[trunc.length-1,1] = "\n" if str[str.length-1,1] == "\n"
  Ncurses::waddstr win, trunc
end

def torrentDisplayName(torrent)
  return "Unknown" if ! torrent 
  name = torrent.recommendedName
  name = bytesToHex(infohash) if ! name || name.length == 0
  name
end

class WindowSizeChangeDetector
  def initialize
    @screenCols = Ncurses.COLS
    @screenLines = Ncurses.LINES
  end

  def ifChanged
    if @screenCols != Ncurses.COLS || @screenLines != Ncurses.LINES
      yield Ncurses.LINES, Ncurses.COLS
    end
  end

  attr_accessor :screenCols
  attr_accessor :screenLines
end

class KeyProcessor
  def key(key)
  end
end

class Screen
  def initialize
    @peerClient = nil
    @screenManager = nil
  end

  def onKey(k)
  end
 
  def screenManager=(m)
    @screenManager = m
  end
 
  attr_accessor :peerClient
end

class SummaryScreen < Screen
  def initialize(window)
    @window = window
    @selectedIndex = -1
    @torrents = nil
  end

  def draw
    Ncurses::werase @window
    Ncurses::wmove(@window, 0,0)
    ColorScheme.apply(ColorScheme::HeadingColorPair)
    Ncurses.attron(Ncurses::A_BOLD)
    waddstrnw @window, "=== QuartzTorrent Downloader  [#{Time.new}] #{$doProfiling ? "PROFILING":""} ===\n\n"
    Ncurses.attroff(Ncurses::A_BOLD) 
    ColorScheme.apply(ColorScheme::NormalColorPair)

    drawTorrents
  end

  def onKey(k)
    if k == Ncurses::KEY_UP
      @selectedIndex -= 1
    elsif k == Ncurses::KEY_DOWN
      @selectedIndex += 1
    end
  end

  def currentTorrent
    return nil if ! @torrents
    @selectedIndex = -1 if @selectedIndex < -1  || @selectedIndex >= @torrents.length
    i = 0
    @torrents.each do |infohash, torrent|
      return torrent if i == @selectedIndex 
      i += 1  
    end
    return nil
  end

  private
  def summaryLine(state, paused, size, uploadRate, downloadRate, complete, total, progress)
    if state == :downloading_metainfo
      "     %12s  Rate: %6s | %6s  Bytes: %4d/%4d Progress: %5s\n" % [state, uploadRate, downloadRate, complete, total, progress]
    else
      if state == :running && complete == total
        state = "running (completed)"
      elsif state == :running && paused
        state = "running (paused)"
      else
        state = state.to_s
      end
      "     %12s  %9s  Rate: %6s | %6s  Pieces: %4d/%4d Progress: %5s\n" % [state, size, uploadRate, downloadRate, complete, total, progress]
    end
  end

  def drawTorrents
    entries = []
   
    if ! @peerClient
      waddstrnw @window, "Loading..."
      return
    end
 
    @torrents = @peerClient.torrentData
    @torrents.each do |infohash, torrent|
      name = torrentDisplayName(torrent)
      #name = torrent.info.name
      #name = bytesToHex(infohash) if ! name || name.length == 0

      pct = "0%"
      if torrent.info
        pct = torrent.completedBytes.to_f / torrent.info.dataLength.to_f * 100.0
        pct = "%.1f%%" % pct
      elsif torrent.state == :downloading_metainfo && torrent.metainfoCompletedLength
        if torrent.metainfoLength
          pct = torrent.metainfoCompletedLength.to_f / torrent.metainfoLength.to_f * 100.0
          pct = "%.1f%%" % pct
        else
          pct = "?%%"
        end
      end

      state = torrent.state

      completePieces = 0
      totalPieces = 0
      dataLength = 0
      if torrent.state == :downloading_metainfo
        completePieces = torrent.metainfoCompletedLength if torrent.metainfoCompletedLength
        totalPieces = torrent.metainfoLength if torrent.metainfoLength
      else
        completePieces = torrent.completePieceBitfield.countSet if torrent.completePieceBitfield
        totalPieces = torrent.info.pieces.length if torrent.info
        dataLength = torrent.info.dataLength if torrent.info
      end

      display = [name + "\n"]
      display.push summaryLine(
        state,
        torrent.paused,
        Formatter.formatSize(dataLength),
        Formatter.formatSpeed(torrent.uploadRate),
        Formatter.formatSpeed(torrent.downloadRate),
        completePieces,
        totalPieces,
        pct)
      entries.push display
    end
    @selectedIndex = -1 if @selectedIndex < -1  || @selectedIndex >= entries.length

    index = 0
    entries.each do |entry|
      entry.each do |line|
        Ncurses.attron(Ncurses::A_REVERSE) if index == @selectedIndex
        waddstrnw @window, line
        Ncurses.attroff(Ncurses::A_REVERSE) if index == @selectedIndex
      end
      index += 1
    end
  end
end

class DetailsScreen < Screen
  def initialize(window)
    @window = window
    @infoHash = nil
  end


  def infoHash=(infoHash)
    @infoHash = infoHash
  end

  def draw
    Ncurses::werase @window
    Ncurses::wmove(@window, 0,0)
    str = "nil"
    if @infoHash
      str = bytesToHex(@infoHash)
    end

    ColorScheme.apply(ColorScheme::HeadingColorPair)
    Ncurses.attron(Ncurses::A_BOLD)
    waddstrnw @window, "=== QuartzTorrent Downloader  [#{Time.new}] #{$doProfiling ? "PROFILING":""} ===\n\n"
    Ncurses.attroff(Ncurses::A_BOLD) 
    ColorScheme.apply(ColorScheme::NormalColorPair)

    if ! @peerClient
      waddstrnw @window, "Loading..."
      return
    end
 
    @torrents = @peerClient.torrentData(@infoHash)
    torrent = nil
    @torrents.each do |infohash, t|
      torrent = t
      break
    end
    if ! torrent
      waddstrnw @window, "No such torrent."
      return
    end

    name = torrentDisplayName(torrent)

    waddstrnw @window, "Details for #{name}\n"

    classified = ClassifiedPeers.new(torrent.peers)
    unchoked = classified.unchokedInterestedPeers.size + classified.unchokedUninterestedPeers.size
    choked = classified.chokedInterestedPeers.size + classified.chokedUninterestedPeers.size
    interested = classified.interestedPeers.size
    uninterested = classified.uninterestedPeers.size
    established = classified.establishedPeers.size
    total = torrent.peers.size

    waddstrnw @window, ("Peers: %3d/%3d  choked %3d:%3d  interested %3d:%3d\n" % [established, total, choked, unchoked, interested, uninterested] )
    waddstrnw @window, "\n"

    waddstrnw @window, "Peer details:\n"

    # Order peers by usefulness.
    torrent.peers.sort! do |a,b|
      rc = stateSortValue(a.state) <=> stateSortValue(b.state)
      rc = b.uploadRate <=> a.uploadRate if rc == 0
      rc = b.downloadRate <=> a.downloadRate if rc == 0
      rc = chokedSortValue(a.amChoked) <=> chokedSortValue(b.amChoked) if rc == 0
      rc
    end

    maxy, maxx = getmaxyx(@window)
    cury, curx = getyx(@window)
    torrent.peers.each do |peer|
      break if cury >= maxy 
      showPeer(peer)
      cury += 1
    end
  end

  private
  def stateSortValue(state)
    if state == :established
      0
    elsif state == :handshaking
      1
    else
      2
    end
  end

  def chokedSortValue(choked)
    if ! choked
      0
    else
      1
    end
  end
  
  def showPeer(peer)

    flags = ""
    flags << (peer.peerChoked ? "chked" : "!chked" )
    flags << ","
    flags << (peer.amChoked ? "chking" : "!chking" )
    flags << ","
    flags << (peer.peerInterested ? "intsted" : "!intsted" )
    flags << ","
    flags << (peer.amInterested ? "intsting" : "!intsting" )

    # host:port, upload, download, state, requestedblocks/maxblocks flags "
    str = "  %-21s Rate: %11s|%-11s %-12s Pending: %4d/%4d %s\n" % 
      [
        "#{peer.trackerPeer.ip}:#{peer.trackerPeer.port}",
        Formatter.formatSpeed(peer.uploadRate),
        Formatter.formatSpeed(peer.downloadRate),
        peer.state.to_s,
        peer.requestedBlocks.length,
        peer.maxRequestedBlocks,
        flags       
      ]
    
    waddstrnw @window, str
  end
end

class DebugScreen < Screen
  def initialize(window)
    @window = window

    @profiler = QuartzTorrent::MemProfiler.new
    @profiler.trackClass QuartzTorrent::Bitfield
    @profiler.trackClass QuartzTorrent::BlockInfo
    @profiler.trackClass QuartzTorrent::BlockState
    @profiler.trackClass QuartzTorrent::ClassifiedPeers
    @profiler.trackClass QuartzTorrent::RequestedBlock
    @profiler.trackClass QuartzTorrent::IncompletePiece
    @profiler.trackClass QuartzTorrent::FileRegion
    @profiler.trackClass QuartzTorrent::PieceMapper
    @profiler.trackClass QuartzTorrent::IOManager
    @profiler.trackClass QuartzTorrent::PieceIO
    @profiler.trackClass QuartzTorrent::PieceManager
    @profiler.trackClass QuartzTorrent::PieceManager::Result
    @profiler.trackClass QuartzTorrent::Formatter
    @profiler.trackClass QuartzTorrent::TrackerClient
    @profiler.trackClass QuartzTorrent::HttpTrackerClient
    @profiler.trackClass QuartzTorrent::InterruptibleSleep
    @profiler.trackClass QuartzTorrent::LogManager
    @profiler.trackClass QuartzTorrent::LogManager::NullIO
    @profiler.trackClass QuartzTorrent::Metainfo
    @profiler.trackClass QuartzTorrent::Metainfo::FileInfo
    @profiler.trackClass QuartzTorrent::Metainfo::Info
    @profiler.trackClass QuartzTorrent::PieceManagerRequestMetadata
    @profiler.trackClass QuartzTorrent::ReadRequestMetadata
    @profiler.trackClass QuartzTorrent::TorrentData
    @profiler.trackClass QuartzTorrent::TorrentDataDelegate
    @profiler.trackClass QuartzTorrent::PeerClientHandler
    @profiler.trackClass QuartzTorrent::PeerClient
    @profiler.trackClass QuartzTorrent::PeerHolder
    @profiler.trackClass QuartzTorrent::ManagePeersResult
    @profiler.trackClass QuartzTorrent::PeerManager
    @profiler.trackClass QuartzTorrent::PeerRequest
    @profiler.trackClass QuartzTorrent::PeerHandshake
    @profiler.trackClass QuartzTorrent::PeerWireMessage
    @profiler.trackClass QuartzTorrent::KeepAlive
    @profiler.trackClass QuartzTorrent::Choke
    @profiler.trackClass QuartzTorrent::Unchoke
    @profiler.trackClass QuartzTorrent::Interested
    @profiler.trackClass QuartzTorrent::Uninterested
    @profiler.trackClass QuartzTorrent::Have
    @profiler.trackClass QuartzTorrent::BitfieldMessage
    @profiler.trackClass QuartzTorrent::Request
    @profiler.trackClass QuartzTorrent::Piece
    @profiler.trackClass QuartzTorrent::Cancel
    @profiler.trackClass QuartzTorrent::Peer
    @profiler.trackClass QuartzTorrent::Rate
    @profiler.trackClass QuartzTorrent::Handler
    @profiler.trackClass QuartzTorrent::OutputBuffer
    @profiler.trackClass QuartzTorrent::IoFacade
    @profiler.trackClass QuartzTorrent::WriteOnlyIoFacade
    @profiler.trackClass QuartzTorrent::IOInfo
    @profiler.trackClass QuartzTorrent::TimerManager
    @profiler.trackClass QuartzTorrent::TimerManager::TimerInfo
    @profiler.trackClass QuartzTorrent::Reactor
    @profiler.trackClass QuartzTorrent::Reactor::InternalTimerInfo
    @profiler.trackClass QuartzTorrent::RegionMap
    @profiler.trackClass QuartzTorrent::TrackerPeer
    @profiler.trackClass QuartzTorrent::TrackerDynamicRequestParams
    @profiler.trackClass QuartzTorrent::TrackerResponse
    @profiler.trackClass QuartzTorrent::TrackerClient
    @profiler.trackClass QuartzTorrent::UdpTrackerClient
    @profiler.trackClass QuartzTorrent::UdpTrackerMessage
    @profiler.trackClass QuartzTorrent::UdpTrackerRequest
    @profiler.trackClass QuartzTorrent::UdpTrackerResponse
    @profiler.trackClass QuartzTorrent::UdpTrackerConnectRequest
    @profiler.trackClass QuartzTorrent::UdpTrackerConnectResponse
    @profiler.trackClass QuartzTorrent::UdpTrackerAnnounceRequest
    @profiler.trackClass QuartzTorrent::UdpTrackerAnnounceResponse

    @lastRefreshTime = nil
    @profilerInfo = nil
  
  end

  def draw
    Ncurses::werase @window
    Ncurses::wmove(@window, 0,0)

    ColorScheme.apply(ColorScheme::HeadingColorPair)
    Ncurses.attron(Ncurses::A_BOLD)
    waddstrnw @window, "=== QuartzTorrent Downloader  [#{Time.new}] ===\n\n"
    Ncurses.attroff(Ncurses::A_BOLD) 
    ColorScheme.apply(ColorScheme::NormalColorPair)

    if @lastRefreshTime.nil? || (Time.new - @lastRefreshTime > 4)
      @profilerInfo = @profiler.getCounts
      @lastRefreshTime = Time.new
    end

    waddstrnw @window, "Memory usage (count of instances of each class):\n"
    @profilerInfo.each do |clazz, count|
      waddstrnw @window, "#{clazz}: #{count}\n"
    end
  end    

end

class LogScreen < Screen
  def initialize(window)
    @window = window
  end

  def draw
    Ncurses::werase @window
    Ncurses::wmove(@window, 0,0)
    waddstrnw @window, "LOG:\n"
    waddstrnw @window, "Blah blah blah"
  end
end

class HelpScreen < Screen
  def initialize(window)
    @window = window
  end

  def draw
    Ncurses::werase @window
    Ncurses::wmove(@window, 0,0)
    waddstrnw @window, "Global Keys:\n\n"
    waddstrnw @window, "  '?':         Show this help screen\n"
    waddstrnw @window, "  's':         Show the summary screen\n"
    waddstrnw @window, "  'd':         Show the memory debug screen\n"
    waddstrnw @window, "  <CTRL-C>:    Exit\n"
    waddstrnw @window, "\nSummary Screen Keys:\n\n"
    waddstrnw @window, "  <UP>,<DOWN>: Change which torrent is currently selected\n"
    waddstrnw @window, "  <ENTER>:     Show the torrent details screen for the currently selected torrent\n"
    waddstrnw @window, "  'p':         Pause/Unpause the currently selected torrent\n"
  end
end

class ScreenManager
  def initialize
    @screens = {}
    @current = nil
    @currentId = nil
  end

  def add(id, screen)
    @screens[id] = screen
    screen.screenManager = self
  end

  def set(id)
    @current = @screens[id]
    @currentId = id
    draw
  end

  def get(id)
    @screens[id]
  end

  def draw
    @current.draw if @current
  end

  def onKey(k)
    @current.onKey(k) if @current
  end

  def peerClient=(peerClient)
    @screens.each do |k,v|
      v.peerClient=peerClient
    end
  end

  def currentId
    @currentId
  end

  attr_reader :current
end

class ColorScheme
  NormalColorPair = 1
  HeadingColorPair = 2

  def self.init
    Ncurses.init_pair(NormalColorPair, Ncurses::COLOR_WHITE, Ncurses::COLOR_BLUE)
    Ncurses.init_pair(HeadingColorPair, Ncurses::COLOR_YELLOW, Ncurses::COLOR_BLUE)
  end  

  def self.apply(colorPair)
    Ncurses.attron(Ncurses::COLOR_PAIR(colorPair));
  end
end

def initializeCurses
  # Initialize Ncurses
  Ncurses.initscr

  # Initialize colors
  Ncurses.start_color
  $log.puts "Terminal supports #{Ncurses.COLORS} colors"

  ColorScheme.init

  #Ncurses.init_pair(ColorScheme::NormalColorPair, Ncurses::COLOR_WHITE, Ncurses::COLOR_BLUE)

  ColorScheme.apply(ColorScheme::NormalColorPair)
  #Ncurses.attron(Ncurses::COLOR_PAIR(1));

  # Turn off line-buffering
  Ncurses::cbreak
  # Don't display characters back
  Ncurses::noecho

  # Don't block on reading characters (block 1 tenths of seconds)
  Ncurses.halfdelay(1)

  # Interpret arrow keys as one character
  Ncurses.keypad Ncurses::stdscr, true


  # Set the window background (used when clearing)
  Ncurses::wbkgdset(Ncurses::stdscr, Ncurses::COLOR_PAIR(ColorScheme::NormalColorPair))
end

def initializeLogging(file)
  QuartzTorrent::LogManager.initializeFromEnv
  FileUtils.rm file if File.exists?(file)
  LogManager.logFile = file
  LogManager.defaultLevel = :info
  LogManager.setLevel "peer_manager", :debug
  LogManager.setLevel "tracker_client", :debug
  LogManager.setLevel "http_tracker_client", :debug
  LogManager.setLevel "udp_tracker_client", :debug
  LogManager.setLevel "peerclient", :debug
  LogManager.setLevel "peerclient.reactor", :info
  #LogManager.setLevel "peerclient.reactor", :debug
  LogManager.setLevel "blockstate", :debug
  LogManager.setLevel "piecemanager", :info
  LogManager.setLevel "peerholder", :debug
end

def help
  puts "Usage: #{$0} [options] <torrent file> [torrent file...]"
  puts
  puts "Download torrents using a simple curses UI. One or more torrent files to download should "
  puts "be passed as arguments."
  puts 
  puts "Options:"
  puts "  --basedir DIR, -d DIR:"
  puts "      Set the base directory where torrents will be written to. The default is" 
  puts "      the current directory."
  puts
  puts "  --port PORT, -p PORT:"
  puts"       Port to listen on for incoming peer connections. Default is 9997"
  puts
  puts "  --upload-limit N, -u N:"
  puts "      Limit upload speed for each torrent to the specified rate in bytes per second. "
  puts "      The default is no limit."
  puts
  puts "  --download-limit N, -d N:"
  puts "      Limit upload speed for each torrent to the specified rate in bytes per second. "
  puts "      The default is no limit."
end

#### MAIN

exception = nil
cursesInitialized = false
begin

  baseDirectory = "."
  port = 9997
  uploadLimit = nil
  downloadLimit = nil
  logfile = "/tmp/download_torrent_curses.log"

  opts = GetoptLong.new(
    [ '--basedir', '-d', GetoptLong::REQUIRED_ARGUMENT],
    [ '--port', '-p', GetoptLong::REQUIRED_ARGUMENT],
    [ '--upload-limit', '-u', GetoptLong::REQUIRED_ARGUMENT],
    [ '--download-limit', '-n', GetoptLong::REQUIRED_ARGUMENT],
    [ '--help', '-h', GetoptLong::NO_ARGUMENT],
  )

  opts.each do |opt, arg|
    if opt == '--basedir'
      baseDirectory = arg
    elsif opt == '--port'
      port = arg.to_i
    elsif opt == '--download-limit'
      downloadLimit = arg.to_i
    elsif opt == '--upload-limit'
      uploadLimit = arg.to_i
    elsif opt == '--help'
      help
      exit 0
    end
  end

  torrents = ARGV
  if torrents.size == 0
    puts "You need to specify a torrent to download."
    exit 1
  end   

  initializeCurses
  cursesInitialized = true
  initializeLogging(logfile)

  sumScr = SummaryScreen.new(Ncurses::stdscr)

  scrManager = ScreenManager.new
  scrManager.add :summary, SummaryScreen.new(Ncurses::stdscr)
  scrManager.add :details, DetailsScreen.new(Ncurses::stdscr)
  scrManager.add :log, LogScreen.new(Ncurses::stdscr)
  scrManager.add :debug, DebugScreen.new(Ncurses::stdscr)
  scrManager.add :help, HelpScreen.new(Ncurses::stdscr)
  scrManager.set :summary

  peerclient = QuartzTorrent::PeerClient.new(baseDirectory)
  peerclient.port = port

  torrents.each do |torrent|
    # Check if the torrent is a torrent file or a magnet URI
    infoHash = nil
    if MagnetURI.magnetURI?(torrent)
      infoHash = peerclient.addTorrentByMagnetURI MagnetURI.new(torrent)
    else
      metainfo = Metainfo.createFromFile(torrent)
      infoHash = peerclient.addTorrentByMetainfo(metainfo)
    end
    peerclient.setDownloadRateLimit infoHash, downloadLimit
    peerclient.setUploadRateLimit infoHash, uploadLimit
  end

  scrManager.peerClient = peerclient

  running = true

  #puts "Creating signal handler"
  Signal.trap('SIGINT') do
    puts "Got SIGINT. Shutting down."
    running = false
  end

  initThread("main")
  if Signal.list.has_key?('USR1')
    Signal.trap('SIGUSR1') do
      QuartzTorrent.logBacktraces
    end
  end

  RubyProf.start if $doProfiling

  #puts "Starting peer client"
  peerclient.start

  while running
    scrManager.draw
    Ncurses::refresh
    key = Ncurses.getch 
    # Since halfdelay actually sleeps up to 1/10 second we can loop back without sleeping and still not burn too much CPU.
    if key != Ncurses::ERR
      if key < 256
        if key.chr == 'l'
          scrManager.set :log
        elsif key.chr == 's'
          scrManager.set :summary
        elsif key.chr == 'd'
          scrManager.set :debug
        elsif key.chr == 'h' || key.chr == '?'
          scrManager.set :help
        elsif key.chr == "\n"
          # Details
          if scrManager.currentId == :summary
            torrent = scrManager.current.currentTorrent
            if torrent
              detailsScreen = scrManager.get :details
              detailsScreen.infoHash = torrent.infoHash
              scrManager.set :details
            end
          end
        elsif key.chr == "p"
          # Pause/unpause
          if scrManager.currentId == :summary
            torrent = scrManager.current.currentTorrent
            peerclient.setPaused(torrent.infoHash, !torrent.paused) if torrent
          end
        else
          scrManager.onKey key
        end
      else
        scrManager.onKey key
      end
    end
  end

  peerclient.stop

  if $doProfiling
    result = RubyProf.stop
    File.open("/tmp/quartz_reactor.prof","w") do |file|
      file.puts "FLAT PROFILE"
      printer = RubyProf::FlatPrinter.new(result)
      printer.print(file)
      file.puts "GRAPH PROFILE"
      printer = RubyProf::GraphPrinter.new(result)
      printer.print(file, {})
    end
  end

rescue LoadError
  exception = $!
rescue
  exception = $!
end

# Restore previous screen
Ncurses.endwin if cursesInitialized

raise exception if exception

