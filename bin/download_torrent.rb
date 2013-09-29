#!/usr/bin/env ruby
$: << "."
require 'fileutils'
require 'getoptlong'
require 'quartz_torrent'

include QuartzTorrent

def help
  puts "Usage: #{$0} [options] <torrent file> [torrent file...]"
  puts
  puts "Download torrents and print logs to stdout. One or more torrent files to download should "
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

baseDirectory = "."
port = 9998
uploadLimit = nil
downloadLimit = nil

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

LogManager.initializeFromEnv
#QuartzTorrent::LogManager.setLevel "peerclient", :info
LogManager.logFile= "stdout"
LogManager.defaultLevel= :info
LogManager.setLevel "peer_manager", :info
LogManager.setLevel "tracker_client", :debug
LogManager.setLevel "http_tracker_client", :debug
LogManager.setLevel "peerclient", :info
LogManager.setLevel "peerclient.reactor", :info
#LogManager.setLevel "peerclient.reactor", :debug
LogManager.setLevel "blockstate", :info
LogManager.setLevel "piecemanager", :info
LogManager.setLevel "peerholder", :debug
LogManager.setLevel "util", :debug
LogManager.setLevel "peermsg_serializer", :info


FileUtils.mkdir baseDirectory if ! File.exists?(baseDirectory)

torrents = ARGV
if torrents.size == 0
  puts "You need to specify a torrent to download."
  exit 1
end   

peerclient = PeerClient.new(baseDirectory)
peerclient.port = port

torrents.each do |torrent|
  puts "Loading torrent #{torrent}"
  infoHash = nil
  # Check if the torrent is a torrent file or a magnet URI
  if MagnetURI.magnetURI?(torrent)
    infoHash = peerclient.addTorrentByMagnetURI MagnetURI.new(torrent)
  else
    metainfo = Metainfo.createFromFile(torrent)
    infoHash = peerclient.addTorrentByMetainfo(metainfo)
  end
  peerclient.setDownloadRateLimit infoHash, downloadLimit
  peerclient.setUploadRateLimit infoHash, uploadLimit
end

running = true

puts "Creating signal handler"
Signal.trap('SIGINT') do
  puts "Got SIGINT. Shutting down."
  running = false
end

QuartzTorrent.initThread("main")
if Signal.list.has_key?('USR1')
  Signal.trap('SIGUSR1') do
    QuartzTorrent.logBacktraces
  end
end

puts "Starting peer client"
peerclient.start

while running do
  sleep 2
  
end

peerclient.stop

