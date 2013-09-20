QuartzTorrent -- A Ruby Bittorrent Library 
==========================================

Like the title says, a bittorrent library implemented in pure ruby. Currently 
the library works, but is still alpha.

Features:
---------

  - BEP 9:  Extension for Peers to Send Metadata Files 
  - BEP 10: Extension Protocol 
  - BEP 15: UDP Tracker support
  - BEP 23: Tracker Returns Compact Peer Lists
  - Upload and download rate limiting
  - Upload ratio enforcement
  - Validated on Linux and Windows

Requirements
------------

This library has been tested with ruby1.9.1. The required gems are listed in the gemspec.

Running the curses client requires rbcurse-core (0.0.14).

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
  - Improve CPU usage. 
  - Implement endgame strategy and support Cancel messages.
  - Change method naming scheme to snake case from camel case.
  - Refactor Metadata.Info into it's own independent class.
  - Documentation
  - Lower log levels currently being used (some warn messages should be info or debug)
  - In peerclient, prefix log messages with torrent infohash, or (truncated) torrent name
  - Implement uTP
    - <http://www.bittorrent.org/beps/bep_0029.html#packet-sizes>
    - <https://forum.utorrent.com/viewtopic.php?id=76640>
    - <https://github.com/bittorrent/libutp>
  
