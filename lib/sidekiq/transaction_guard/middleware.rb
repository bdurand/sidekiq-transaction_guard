# frozen_string_literal: true

module Sidekiq
  module TransactionGuard
    # Sidekiq client middleware that will warn/error when workers are called inside of
    # a database transaction.
    #
    # This middleware can read `sidekiq_options` set on the worker for
    # `:transaction_guard` and `:notify_in_transaction` which will override
    # the default behavior set in `Sidekiq::TransactionGuard.mode` and
    # `Sidekiq::TransactionGuard.notify` respectively.
    class Middleware
      def call(worker_class, job, queue, redis_pool)
        # Check if we need to log this. Also, convert worker_class to its actual class
        log_transaction(worker_class.constantize, job) if in_transaction?

        yield
      end

      private

      def worker_mode(worker_class)
        read_sidekiq_option(worker_class, :transaction_guard) || Sidekiq::TransactionGuard.mode
      end

      def in_transaction?
        Sidekiq::TransactionGuard.in_transaction?
      end

      def notify_block(worker_class)
        handler = read_sidekiq_option(worker_class, :notify_in_transaction)
        if handler
          handler
        elsif handler == false
          nil
        else
          Sidekiq::TransactionGuard.notify_block
        end
      end

      def read_sidekiq_option(worker_class, option_name)
        options = worker_class.sidekiq_options_hash
        options[option_name.to_s] if options
      end

      def notify!(worker_class, job)
        notify_handler = notify_block(worker_class)
        if notify_handler
          begin
            notify_handler.call(job)
          rescue => e
            if Sidekiq.logger
              Sidekiq.logger.error(e)
            else
              STDERR.write("ERROR on Sidekiq::TransactionGuard notify block for #{worker_class}: #{e.inspect}\n")
            end
          end
        end
      end

      def log_transaction(worker_class, job)
        mode = worker_mode(worker_class)
        if mode != :disabled
          message = "#{worker_class.name} was called from inside a database transaction"
          if mode == :error
            raise Sidekiq::TransactionGuard::InsideTransactionError.new(message)
          else
            logger = Sidekiq.logger unless mode == :stderr
            if logger
              logger.warn(message)
            else
              STDERR.write("WARNING #{message}\n")
            end
            notify!(worker_class, job)
          end
        end
      end
    end
  end
end
