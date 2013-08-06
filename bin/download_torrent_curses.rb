#!/usr/bin/env ruby
$: << "."
require 'fileutils'
require 'getoptlong'
require "ncurses"
require 'src/peerclient'
require 'src/formatter'

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
  end

  def onKey(k)
  end
  
  attr_accessor :peerClient
end

class SummaryScreen < Screen
  def initialize(window)
    @window = window
    @selectedIndex = -1
  end

  def draw
    Ncurses::werase @window
    Ncurses::wmove(@window, 0,0)
    waddstrnw @window, "Time: #{Time.new}\n"

    drawTorrents
  end

  def onKey(k)
    if k == Ncurses::KEY_UP
      @selectedIndex -= 1
    elsif k == Ncurses::KEY_DOWN
      @selectedIndex += 1
    end
  end

  private
  def summaryLine(state, size, uploadRate, downloadRate, progress)
    "     %12s  %9s  Rate: %6s | %6s  Progress: %5s\n" % [state, size, uploadRate, downloadRate, progress]
  end

  def drawTorrents
    entries = []
   
    if ! @peerClient
      waddstrnw @window, "Loading..."
      return
    end
 
    torrents = @peerClient.torrentData
    torrents.each do |infohash, torrent|
      name = torrent.metainfo.info.name
      name = bytesToHex(infohash) if ! name || name.length == 0

      pct = torrent.completedBytes.to_f / torrent.metainfo.info.dataLength.to_f * 100.0
      pct = "%.1f%%" % pct

      state = torrent.state
      if state == :running && torrent.completedBytes == torrent.metainfo.info.dataLength
        state = "running (completed)"
      else
        state = state.to_s
      end

      display = [name + "\n"]
      display.push summaryLine(
        state, 
        Formatter.formatSize(torrent.metainfo.info.dataLength),
        Formatter.formatSpeed(torrent.uploadRate),
        Formatter.formatSpeed(torrent.downloadRate),
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
  end

  def draw
    Ncurses::werase @window
    Ncurses::wmove(@window, 0,0)
    waddstrnw @window, "Thing_being_downloaded.zip\n"
    waddstrnw @window, "Peers: 50 [4 un, 46 choked] [30 interested, 20 un]"
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
  end

  def add(id, screen)
    @screens[id] = screen
  end

  def set(id)
    @current = @screens[id]
    draw
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
end

def initializeCurses
  # Initialize Ncurses
  Ncurses.initscr

  # Initialize colors
  Ncurses.start_color
  $log.puts "Terminal supports #{Ncurses.COLORS} colors"

  Ncurses.init_pair(1, Ncurses::COLOR_WHITE, Ncurses::COLOR_BLUE)

  Ncurses.attron(Ncurses::COLOR_PAIR(1));

  # Turn off line-buffering
  Ncurses::cbreak
  # Don't display characters back
  Ncurses::noecho

  # Don't block on reading characters (block 1 tenths of seconds)
  Ncurses.halfdelay(1)

  # Interpret arrow keys as one character
  Ncurses.keypad Ncurses::stdscr, true


  # Set the window background (used when clearing)
  Ncurses::wbkgdset(Ncurses::stdscr, Ncurses::COLOR_PAIR(1))
end

def initializeLogging(file)
  QuartzTorrent::LogManager.initializeFromEnv
  FileUtils.rm file if File.exists?(file)
  LogManager.logFile = file
  LogManager.defaultLevel = :info
  LogManager.setLevel "peer_manager", :info
  LogManager.setLevel "tracker_client", :debug
  LogManager.setLevel "http_tracker_client", :debug
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
          scrManager.set :details
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

