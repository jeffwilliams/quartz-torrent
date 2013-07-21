#!/usr/bin/env ruby
system "sudo tshark -R bittorrent -V -i lo | less"
