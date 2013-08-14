$: << "."
require 'fileutils'
require 'getoptlong'
require 'quartz_torrent'

include QuartzTorrent

baseDirectory = "tmp"
port = 9998

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

LogManager.initializeFromEnv
#QuartzTorrent::LogManager.setLevel "peerclient", :info
LogManager.logFile= "stdout"
LogManager.defaultLevel= :info
LogManager.setLevel "peer_manager", :info
LogManager.setLevel "tracker_client", :debug
LogManager.setLevel "http_tracker_client", :debug
LogManager.setLevel "peerclient", :debug
LogManager.setLevel "peerclient.reactor", :info
#LogManager.setLevel "peerclient.reactor", :debug
LogManager.setLevel "blockstate", :info
LogManager.setLevel "piecemanager", :info
LogManager.setLevel "peerholder", :debug
LogManager.setLevel "util", :debug

FileUtils.mkdir baseDirectory if ! File.exists?(baseDirectory)

torrent = ARGV[0]
if ! torrent
  torrent = "tests/data/testtorrent.torrent"
end
puts "Loading torrent #{torrent}"

metainfo = Metainfo.createFromFile(torrent)
peerclient = PeerClient.new(baseDirectory)
peerclient.port = port
peerclient.addTorrentByMetainfo(metainfo)


running = true

puts "Creating signal handler"
Signal.trap('SIGINT') do
  puts "Got SIGINT. Shutting down."
  running = false
end

initThread("main")
Signal.trap('SIGUSR1') do
  QuartzTorrent.logBacktraces
end

puts "Starting peer client"
peerclient.start

while running do
  sleep 2
  
end

peerclient.stop

