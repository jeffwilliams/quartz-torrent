QuartzTorrent -- A Ruby Bittorrent Library 
==========================================

[![Gem Version](https://badge.fury.io/rb/quartz_torrent.png)](http://badge.fury.io/rb/quartz\_torrent)

Like the title says, a bittorrent library implemented in pure ruby. 

Features:
---------

  - BEP 9:  Extension for Peers to Send Metadata Files 
  - BEP 10: Extension Protocol 
  - BEP 15: UDP Tracker support
  - BEP 23: Tracker Returns Compact Peer Lists
  - Upload and download rate limiting
  - Upload ratio enforcement
  - Upload duration limit
  - Torrent Queueing

Requirements
------------

This library has been tested with ruby1.9.1. The required gems are listed in the gemspec.

Running the curses client requires rbcurse-core (0.0.14).

Getting Started
---------------

How to use the library is best illustrated with an example. The sample program below touches on all the
major ideas.

    require 'quartz_torrent'
    include QuartzTorrent
    
    # Direct logging to stdout at info level
    LogManager.setup do
      setLogfile "stdout"
      setDefaultLevel :info
    end
    
    # When CTRL-C is pressed, shut down
    running = true
    Signal.trap('SIGINT') do
      puts "Got SIGINT. Shutting down."
      running = false
    end
    
    # Create MagnetURI from first argument
    magnet = MagnetURI.new(ARGV[0])
    
    # Create a PeerClient that downloads to the current directory. 
    # This is the main API, and implements the Bittorrent peer protocol. 
    peerclient = PeerClient.new(".")
    peerclient.port = 5555
    peerclient.addTorrentByMagnetURI magnet
    
    # Start the peerclient in another thread.
    peerclient.start
    
    while running do
      peerclient.torrentData.each do |infohash, torrent|
        name = torrent.recommendedName
        pct = 0
        if torrent.info
          pct = (torrent.completedBytes.to_f / torrent.info.dataLength.to_f * 100.0).round(2)
        end
        puts "#{name}: #{pct}%"
      end
      sleep 2
    end
    
    peerclient.stop

Logging is configured using QuartzTorrent::LogManager. Logs can be sent to stdout, stderr, or file. Individual loggers can be set to different levels. 

The QuartzTorrent::PeerClient class is the main interface for downloading and uploading torrents. The PeerClient constructor takes the path to the 
directory into which torrents should be downloaded. Torrents may be  added to the PeerClient as Magnet links, or .torrent file contents before or after 
the PeerClient is stared. When started, the PeerClient runs asynchronously in a separate thread. Information regarding the running torrents is retrieved
with the PeerClient::torrentData method.

More elaborate examples can be found in `bin/quartztorrent_download` and `bin/quartztorrent_download_curses`. 

Running Tests
-------------

Run the tests as:

    rake test

You can run a specific test using, i.e.:

    rake test TEST=tests/test_reactor.rb

And a specific test case in a test using:

    ruby1.9.1 -Ilib tests/test_reactor.rb -n test_client


To-Do
-----
  - Implement uTP
    - <http://www.bittorrent.org/beps/bep_0029.html#packet-sizes>
    - <https://forum.utorrent.com/viewtopic.php?id=76640>
    - <https://github.com/bittorrent/libutp>
  
