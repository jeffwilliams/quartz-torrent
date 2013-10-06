#!/usr/bin/env ruby
require 'getoptlong'
require 'quartz_torrent/magnet'
require 'quartz_torrent/metainfo'

include QuartzTorrent

def help
  puts "Usage: #{$0} <torrentfile>"
  puts "Output a magnet link based on the information found in torrentfile (which should be a .torrent file)"
  puts 
end

opts = GetoptLong.new(
  [ '--help', '-h', GetoptLong::NO_ARGUMENT],
)

opts.each do |opt, arg|
  if opt == '--help'
    help
  end
end

torrent = ARGV[0]
if ! torrent
  help
  exit 1
end   

metainfo = Metainfo.createFromFile(torrent)
puts MagnetURI.encodeFromMetainfo(metainfo)

