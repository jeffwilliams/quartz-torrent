
# Implements a counting semaphore.
class Semaphore
  # Create a new semaphore initialized to the specified count.
  def initialize(count = 0)
    @mutex = Mutex.new
    @count = count
    @sleeping = []
  end

  # Wait on the semaphore. If the count zero or below, the calling thread blocks.
  # Optionally a timeout in seconds can be specified. This method returns true if the wait
  # ended because of a signal, and false if it ended because of a timeout.
  def wait(timeout = nil)
    result = true
    c = nil
    @mutex.synchronize do
      @count -= 1
      if @count < 0
        @sleeping.push Thread.current
        @mutex.sleep(timeout)
      end
    end
    if timeout
      # If we had a timeout we may have woken due to it expiring rather than
      # due to signal being called. In that case we need to remove ourself from the sleepers.
      @mutex.synchronize do
        i = @sleeping.index(Thread.current)
        if i
          @count += 1
          @sleeping.delete_at(i)
          result = false
        end
      end
    end
    result
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

  # Testing method.
  def count
    @count
  end
end

