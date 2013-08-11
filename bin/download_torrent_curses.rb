#!/usr/bin/env ruby
require 'fileutils'
require 'getoptlong'
require "ncurses"
require 'quartz_torrent'
require 'quartz_torrent/memprofiler'
require 'quartz_torrent/formatter'



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
  name = torrent.metainfo.info.name
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
    waddstrnw @window, "=== QuartzTorrent Downloader  [#{Time.new}] ===\n\n"
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
  def summaryLine(state, size, uploadRate, downloadRate, completePieces, totalPieces, progress)
    "     %12s  %9s  Rate: %6s | %6s  Pieces: %4d/%4d Progress: %5s\n" % [state, size, uploadRate, downloadRate, completePieces, totalPieces, progress]
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
      #name = torrent.metainfo.info.name
      #name = bytesToHex(infohash) if ! name || name.length == 0

      pct = torrent.completedBytes.to_f / torrent.metainfo.info.dataLength.to_f * 100.0
      pct = "%.1f%%" % pct

      state = torrent.state
      if state == :running && torrent.completedBytes == torrent.metainfo.info.dataLength
        state = "running (completed)"
      else
        state = state.to_s
      end

      completePieces = 0
      completePieces = torrent.completePieceBitfield.countSet if torrent.completePieceBitfield
      totalPieces = torrent.metainfo.info.pieces.length

      display = [name + "\n"]
      display.push summaryLine(
        state, 
        Formatter.formatSize(torrent.metainfo.info.dataLength),
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
    waddstrnw @window, "=== QuartzTorrent Downloader  [#{Time.new}] ===\n\n"
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
    @profiler.trackClass QuartzTorrent::Rate::Sample
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

#### MAIN

exception = nil
begin

  baseDirectory = "tmp"
  port = 9997
  logfile = "/tmp/download_torrent_curses.log"

  opts = GetoptLong.new(
    [ '--basedir', '-d', GetoptLong::REQUIRED_ARGUMENT],
    [ '--port', '-p', GetoptLong::REQUIRED_ARGUMENT],
  )

  opts.each do |opt, arg|
    if opt == '--basedir'
      baseDirectory = arg
    elsif opt == '--port'
      port = arg.to_i
    end
  end

  torrent = ARGV[0]
  if ! torrent
    puts "You need to specify a torrent to download."
    exit 1
  end   

  initializeCurses
  initializeLogging(logfile)

  sumScr = SummaryScreen.new(Ncurses::stdscr)

  scrManager = ScreenManager.new
  scrManager.add :summary, SummaryScreen.new(Ncurses::stdscr)
  scrManager.add :details, DetailsScreen.new(Ncurses::stdscr)
  scrManager.add :log, LogScreen.new(Ncurses::stdscr)
  scrManager.add :debug, DebugScreen.new(Ncurses::stdscr)
  scrManager.set :summary

  #puts "Loading torrent #{torrent}"
  metainfo = QuartzTorrent::Metainfo.createFromFile(torrent)
  trackerclient = QuartzTorrent::TrackerClient.create(metainfo, false)
  trackerclient.port = port
  peerclient = QuartzTorrent::PeerClient.new(baseDirectory)
  peerclient.port = port
  peerclient.addTrackerClient(trackerclient)

  scrManager.peerClient = peerclient

  running = true

  #puts "Creating signal handler"
  Signal.trap('SIGINT') do
    puts "Got SIGINT. Shutting down."
    running = false
  end

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
        elsif key.chr == "\n"
          # Details
          if scrManager.currentId == :summary
            torrent = scrManager.current.currentTorrent
            if torrent
              detailsScreen = scrManager.get :details
              detailsScreen.infoHash = torrent.metainfo.infoHash
              scrManager.set :details
            end
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

rescue LoadError
  exception = $!
rescue
  exception = $!
end

# Restore previous screen
Ncurses.endwin

raise exception if exception

