module QuartzTorrent
 
  # Metadata associated with outstanding requests to the PieceManager (asynchronous IO management).
  class PieceManagerRequestMetadata
    def initialize(type, data)
      @type = type
      @data = data
    end
    attr_accessor :type
    attr_accessor :data
  end
end
