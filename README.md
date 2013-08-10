QuartzTorrent -- A Ruby Bittorrent Library 
==========================================

Like the title says, a bittorrent library implemented in pure ruby. Currently 
the library works, but is still alpha.

To-Do
-----

  - Shutdown takes a long time
  - Implement endgame strategy
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
  - Allow pausing/unpausing torrents
  - Package library as a gem
  - Implement rate limiting
  - Documentation
  - Help screen in curses downloader

Requirements
------------

ruby 1.9.1
bencode (0.8.0)
pqueue (2.0.2)
rbcurse-core (0.0.14)

Running Tests
-------------

Run the tests as i.e.:

ruby1.9.1 tests/test_filemanager.rb

