require "quartz_torrent/log.rb"

module QuartzTorrent
  class TorrentQueue
    # The maxIncomplete and maxActive parameters specify how many torrents may be unpaused and unqueued at once.
    # Parameter maxActive is the total maximum number of active torrents (unpaused, unqueued), and maxIncomplete is a subset of 
    # maxActive that are incomplete and thus downloading (as opposed to only uploading). An exception is thrown if
    # maxIncomplete > maxActive.
    # 
    def initialize(maxIncomplete, maxActive)
      raise "The maximum number of running torrents may not be larger than the maximum number of unqueued torrents" if maxIncomplete > maxActive
      @maxIncomplete = maxIncomplete
      @maxActive = maxActive
      @queue = []
      @logger = LogManager.getLogger("queue")
    end

    # Compute which torrents can now be unqueued based on the state of running torrents.
    # Parameter torrentDatas should be an array of TorrentData that the decision will be based off. At a minimum
    # these items should respond to 'paused', 'queued', 'state', 'queued=' 
    def dequeue(torrentDatas)
      numActive = 0
      numIncomplete = 0
      torrentDatas.each do |torrentData|
        next if torrentData.paused || torrentData.queued
        numIncomplete += 1 if incomplete?(torrentData)
        numActive += 1
      end
      @logger.debug "incomplete: #{numIncomplete}/#{@maxIncomplete} active: #{numActive}/#{@maxActive}"
      @logger.debug "Queue contains #{size} torrents"

      torrents = []

      while numActive < @maxActive
        torrentData = nil
        if numIncomplete < @maxIncomplete
          # Unqueue first incomplete torrent from queue
          torrentData = dequeueFirstMatching{ |torrentData| incomplete?(torrentData)}
          @logger.debug "#{torrentData ? "dequeued" : "failed to dequeue"} an incomplete torrent"
          numIncomplete += 1 if torrentData
        end
        if ! torrentData
          # Unqueue first complete (uploading) torrent from queue
          torrentData = dequeueFirstMatching{ |torrentData| !incomplete?(torrentData)}
          @logger.debug "#{torrentData ? "dequeued" : "failed to dequeue"} a complete torrent"
        end
        numActive += 1 if torrentData
        
        if torrentData
          torrentData.queued = false
          torrents.push torrentData
        else
          break
        end
      end

      @logger.debug "Will dequeue #{torrents.size}"

      torrents
    end

    def push(torrentData)
      torrentData.queued = true
      @queue.push torrentData
    end

    def unshift(torrentData)
      torrentData.queued = true
      @queue.unshift torrentData
    end

    def size
      @queue.size
    end

    private

    def incomplete?(torrentData)
      torrentData.state != :uploading
    end

    def dequeueFirstMatching
      index = @queue.index{ |torrentData| yield(torrentData) }
      if index
        @queue.delete_at index
      else
        nil
      end
    end
  end
end
