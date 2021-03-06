module ScoutApm
  module Instruments
    class DelayedJob
      attr_reader :logger

      def initialize(logger=ScoutApm::Agent.instance.logger)
        @logger = logger
        @installed = false
      end

      def installed?
        @installed
      end

      def install
        @installed = true
        if defined?(::Delayed::Worker)
          ::Delayed::Worker.class_eval do
            include ScoutApm::Tracer
            include ScoutApm::Instruments::DelayedJobInstruments
            alias run_without_scout_instruments run
            alias run run_with_scout_instruments
          end
        end
      end
    end

    module DelayedJobInstruments
      def run_with_scout_instruments(job)
        scout_method_name = method_from_handler(job.handler)
        queue = job.queue
        latency = (Time.now.to_f - job.created_at.to_f) * 1000

        ScoutApm::Agent.instance.store.track_one!("Queue", queue, 0, {:extra_metrics => {:latency => latency}})
        req = ScoutApm::RequestManager.lookup
        req.start_layer( ScoutApm::Layer.new("Job", scout_method_name) )

        begin
          run_without_scout_instruments(job)
        rescue
          req.error!
          raise
        ensure
          req.stop_layer
        end
      end

      def method_from_handler(handler)
        job_handler = YAML.load(handler)
        klass = job_handler.object.name
        method = job_handler.method_name
        "#{klass}##{method}"
      end
    end
  end
end
