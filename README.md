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

To-Do
-----

  - Shutdown takes a long time
  - Implement endgame strategy and support Cancel messages.
  - Currently when we request blocks we request a fixed amount from the first peer returned from the findRequestableBlocks
    call. We should spread the requests out to other peers as well if we have saturated the first peer's connection.
    We could tell by the peer's upload rate: upload_rate/(block_size/request_blocks_period) is the ratio of peer's measured
    upload versus our expected upload based on our requests. If this ratio is 1 we are requesting at the rate that the 
    peer can upload to us. If it is < 0 we are requesting faster than the peer can provide. We can keep increasing the
    amount we request from the peer as long as the ratio stays at almost 1. If it drops below a threshold then we should scale
    back our requesting.

      upload_rate/(block_size/request_blocks_period)

    Alternately, a simpler approach could be to begin by queueing 100 requests, and scaling up or back based on the amount
    remaining next iteration.
  - Magnet links support. Implement BEP 10, BEP 9, BEP 5(?)
    - BEP 9: Extension for Peers to Send Metadata Files
      - Check hash when completed.
      - Begin downloading when completed

  - Refactor Metadata.Info into it's own independent class.
  - Add type checking in public APIs
  - Allow pausing/unpausing torrents
  - Package library as a gem
  - Implement rate limiting
  - Documentation
  - Help screen in curses downloader
  - Trackers can return the same peer multiple times (same ip and port). Detect this and remove dups.
  - Lower log levels currently being used (some warn messages should be info or debug)
  - In peerclient, prefix messages with torrent infohash


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


