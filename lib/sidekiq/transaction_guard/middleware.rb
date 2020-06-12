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
        if in_transaction?
          worker_class = worker_class.constantize if worker_class.is_a?(String)
          log_transaction(worker_class, job)
        end
        yield
      end

      private

      def worker_mode(job)
        read_sidekiq_option(job, :transaction_guard) || Sidekiq::TransactionGuard.mode
      end

      def in_transaction?
        Sidekiq::TransactionGuard.in_transaction?
      end

      def notify_block(job)
        handler = read_sidekiq_option(job, :notify_in_transaction)
        if handler
          handler
        elsif handler == false
          nil
        else
          Sidekiq::TransactionGuard.notify_block
        end
      end

      def read_sidekiq_option(job, option_name)
        # options = worker_class.sidekiq_options_hash
        job[option_name.to_s]
      end

      def notify!(worker_class, job)
        notify_handler = notify_block(job)
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
        mode = worker_mode(job)
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
