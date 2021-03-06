module ScoutApm
  class RequestQueueTime < LayerConverterBase
    HEADERS = %w(X-Queue-Start X-Request-Start X-QUEUE-START X-REQUEST-START x-queue-start x-request-start)

    # Headers is a hash of request headers.  In Rails, request.headers would be appropriate
    def initialize(request)
      super(request)
      @headers = request.headers
    end

    def call
      return {} unless headers

      raw_start = locate_timestamp
      return {} unless raw_start

      parsed_start = parse(raw_start)
      return {} unless parsed_start

      request_start = root_layer.start_time
      queue_time = (request_start - parsed_start).to_f

      # If we end up with a negative value, just bail out and don't report anything
      return {} if queue_time < 0

      meta = MetricMeta.new("QueueTime/Request", {:scope => scope_layer.legacy_metric_name})
      stat = MetricStats.new(true)
      stat.update!(queue_time)

      { meta => stat }
    end

    private

    attr_reader :headers

    # Looks through the possible headers with this data, and extracts the raw
    # value of the header
    # Returns nil if not found
    def locate_timestamp
      return nil unless headers

      header = HEADERS.find { |candidate| headers[candidate] }
      if header
        data = headers[header]
        data.to_s.gsub(/(t=|\.)/, '')
      else
        nil
      end
    end

    # Returns a timestamp in fractional seconds since epoch
    def parse(time_string)
      Time.at("#{time_string[0,10]}.#{time_string[10,13]}".to_f)
    end
  end
end
