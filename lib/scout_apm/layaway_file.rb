# Logic for the serialized file access
module ScoutApm
  class LayawayFileLock
    attr_reader :depth

    def initialize
      @depth = 0
      @obtain_block  = lambda {}
      @release_block = lambda {}
    end

    def locked?
      depth > 0
    end

    def increment!
      if depth == 0
        ScoutApm::Agent.instance.logger.debug("Obtaining Layaway Lock")
        @obtain_block.call
        @locked_obtained_at = Time.now
        @depth += 1
      else
        @depth += 1
        ScoutApm::Agent.instance.logger.debug("Incremented Layway lock count to #{depth}")
      end
    end

    def decrement!
      @depth -= 1
      if depth == 0
        ScoutApm::Agent.instance.logger.debug("Releasing Layaway file Lock")
        @release_block.call
        ScoutApm::Agent.instance.logger.debug("Held lock for: #{(Time.now.to_f - @locked_obtained_at.to_f).round(3)} seconds")
        @locked_obtained_at = nil
      else
        ScoutApm::Agent.instance.logger.debug("Decremented Layway lock count to #{depth}")
      end
    end

    def obtain_block(&block)
      @obtain_block = block
      self
    end

    def release_block(&block)
      @release_block = block
      self
    end
  end

  class LayawayFile
    attr_reader :lock

    def initialize
      @lock = make_lock
    end

    def log_time(thing)
      t = Time.now
      result = yield
      ScoutApm::Agent.instance.logger.debug("#{thing} took #{(Time.now.to_f - t.to_f).round(3)} seconds")
      result
    end

    def make_lock
      LayawayFileLock.new.obtain_block do
        log_time "Opening file" do
          @f = File.open(path, File::RDWR | File::CREAT)
        end

        log_time "Obtaining exclusive lock" do
          @f.flock(File::LOCK_EX)
        end

        @data = get_data(@f) # After locking, read in the data
      end.release_block do
        dumped = log_time "Marshalling data" do
          dumped = dump(@data)
        end

        log_time "Writing data" do
          write(@f, dump(@data)) # Before unlocking, write the data back to the file
        end

        log_time "Releasing lock" do
          @f.flock(File::LOCK_UN)
        end

        @f.close
        @f = nil
      end
    end

    def path
      ScoutApm::Agent.instance.config.value("data_file") ||
        "#{ScoutApm::Agent.instance.default_log_path}/scout_apm.db"
    end

    # Only get the lock at the outer layer, and let inner layers use it.
    # Maintain a count of how many layers of locks we're in, so we know when we
    # exit the last one, and can release it.
    def with_lock
      lock.increment!
      log_time "In logic code" do
        yield
      end
    ensure
      lock.decrement!
    end

    def read_and_write
      with_lock do
        @data = (yield @data)
      end
    rescue Errno::ENOENT, Exception  => e
      ScoutApm::Agent.instance.logger.error("Unable to access the layaway file [#{e.message}]. " +
                                            "The user running the app must have read & write access. " +
                                            "Change the path by setting the `data_file` key in scout_apm.yml"
                                           )
      ScoutApm::Agent.instance.logger.debug(e.backtrace.join("\n\t"))
    end

    ###########################################################################################################
    ###########################################################################################################


    def dump(object)
      Marshal.dump(object)
    end

    def load(dump)
      if dump.size == 0
        ScoutApm::Agent.instance.logger.debug("No data in layaway file.")
        return nil
      end
      Marshal.load(dump)
    rescue ArgumentError, TypeError => e
      ScoutApm::Agent.instance.logger.debug("Error loading data from layaway file: #{e.inspect}")
      ScoutApm::Agent.instance.logger.debug(e.backtrace.inspect)
      nil
    end

    def get_data(f)
      data = log_time "Reading file data" do
        data = read_until_end(f)
      end

      ScoutApm::Agent.instance.logger.debug("Reading bytes: #{data.length} from layaway file")

      log_time "Parsing data" do
        load(data)
      end
    end

    def write(f, string)
      ScoutApm::Agent.instance.logger.debug("Writing bytes: #{string.length} to layaway file")
      f.rewind
      f.truncate(0)
      bytes_written = 0
      while (bytes_written < string.length)
        bytes_written += f.write_nonblock(string)
      end
    rescue Errno::EAGAIN, Errno::EINTR
      IO.select(nil, [f])
      retry
    end

    def read_until_end(f)
      contents = ""
      while true
        contents << f.read_nonblock(10_000)
      end
    rescue Errno::EAGAIN, Errno::EINTR
      IO.select([f])
      retry
    rescue EOFError
      contents
    end
  end
end


