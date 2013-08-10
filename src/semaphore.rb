
# Implements a counting semaphore.
class Semaphore
  # Create a new semaphore initialized to the specified count.
  def initialize(count = 0)
    @mutex = Mutex.new
    @count = count
    @sleeping = []
  end

  # Wait on the semaphore. If the count zero or below, the calling thread blocks.
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

  # Signal the semaphore. If the count is below zero the waiting threads are woken.
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

