
module ScoutApm
  class ConnectionPoolTracer
    def install
      if defined?(ActiveRecord) && defined?(ActiveRecord::ConnectionAdapters) && defined?(ActiveRecord::ConnectionAdapters::ConnectionPool)

        STDOUT.puts("Installing Debug AR Connection Pool Tracer")

        ActiveRecord::ConnectionAdapters::ConnectionPool.class_eval do
          def release_connection_with_logging(with_id=current_connection_id)
            ScoutApm::Agent.instance.logger.info("AR Connection Trace: release_connection for thread: #{with_id}. #{caller.join("\n\t")}")
            release_connection_without_logging(with_id)
          end
          alias_method :release_connection_without_logging, :release_connection
          alias_method :release_connection, :release_connection_with_logging

          def checkout_with_logging
            ScoutApm::Agent.instance.logger.info("AR Connection Trace: checkout connection for thread: #{current_connection_id}:  #{caller.join("\n\t")}")
            checkout_without_logging
          end
          alias_method :checkout_without_logging, :checkout
          alias_method :checkout, :checkout_with_logging
        end
      end
    end
  end
end
