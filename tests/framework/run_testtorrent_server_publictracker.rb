#!/usr/bin/env ruby

CompleteFile = "../data/testtorrent"
MetainfoFile = "../data/testtorrent2.torrent"

puts "Starting downloader that has full file"
#exec "btdownloadheadless --saveas #{CompleteFile} #{MetainfoFile}"
exec "btdownloadcurses --saveas #{CompleteFile} #{MetainfoFile}"




