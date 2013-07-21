#!/usr/bin/env ruby

puts "Making torrent file"
#exec "btdownloadheadless --saveas #{CompleteFile} #{MetainfoFile}"
Dir.chdir "../data"
exec "btmakemetafile testtorrent http://localhost:8001/announce"




