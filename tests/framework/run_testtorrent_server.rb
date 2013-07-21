#!/usr/bin/env ruby

CompleteFile = "../data/testtorrent"
MetainfoFile = "../data/testtorrent.torrent"

puts "Starting downloader that has full file"
#exec "btdownloadheadless --saveas #{CompleteFile} #{MetainfoFile}"
exec "btdownloadcurses --spew 9 --saveas #{CompleteFile} #{MetainfoFile}"




