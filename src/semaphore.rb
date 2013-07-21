
class Semaphore
  def initialize(count = 0)
    @mutex = Mutex.new
    @count = count
    @sleeping = []
  end

  def wait
    c = nil
    @mutex.synchronize do
      @count -= 1
      c = @count
    end

    if c < 0
      @mutex.synchronize do
        @sleeping.push Thread.current
      end
      Thread.stop
    end
  end

  def signal
    c = nil
    @mutex.synchronize do
      c = @count
      @count += 1
    end
    if c < 0 
      t = nil
      @mutex.synchronize do
        t = @sleeping.shift
      end
      t.wakeup if t
    end
  end
end

