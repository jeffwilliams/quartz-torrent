
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
      if @count < 0
        @sleeping.push Thread.current
        @mutex.sleep
      end
    end
  end

  # Signal the semaphore. If the count is below zero the waiting threads are woken.
  def signal
    c = nil
    @mutex.synchronize do
      c = @count
      @count += 1
      if c < 0 
        t = @sleeping.shift
        t.wakeup if t
      end
    end
  end
end

