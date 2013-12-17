module QuartzTorrent
  class Alarm
    def initialize(id, details)
      @details = details
      @time = Time.new
    end

    attr_accessor :id
    attr_accessor :details
    attr_accessor :time
  end

  class Alarms
    def initialize
      @alarms = {}
    end

    # Raise a new alarm, or overwrite the existing alarm with the same id if one exists.
    def raise(alarm)
      @alarms[alarm.id] = alarm
    end

    def clear(alarm)
      if alarm.is_a?(Alarm)
        @alarms.delete alarm.id
      else
        # Assume variable `alarm` is an id.
        @alarms.delete alarm
      end
    end

    def all
      @alarms.values
    end
  end
end
