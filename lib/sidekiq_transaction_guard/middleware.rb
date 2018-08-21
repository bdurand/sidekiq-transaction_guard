# frozen_string_literal: true

module SidekiqTransactionGuard
  # Sidekiq client middleware that will warn/error when workers are called inside of
  # a database transaction.
  #
  # This middleware can read `sidekiq_options` set on the worker for
  # `:transaction_guard` and `:notify_in_transaction` which will override
  # the default behavior set in `SidekiqTransactionGuard.mode` and
  # `SidekiqTransactionGuard.notify` respectively.
  class Middleware
    def call(worker_class, job, queue, redis_pool)
      log_transaction(worker_class.constantize) if in_transaction?

      yield
    end

    private

    def worker_mode(worker_class)
      read_sidekiq_option(worker_class, :transaction_guard) || SidekiqTransactionGuard.mode
    end

    def in_transaction?
      SidekiqTransactionGuard.in_transaction?
    end

    def notify_block(worker_class)
      handler = read_sidekiq_option(worker_class, :notify_in_transaction)
      if handler
        handler
      elsif handler == false
        nil
      else
        SidekiqTransactionGuard.notify_block
      end
    end

    def read_sidekiq_option(worker_class, option_name)
      options = worker_class.sidekiq_options
      options.fetch(option_name.to_s, options[option_name])
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
            $stderr.write("ERROR on SidekiqTransactionGuard notify block for #{worker_class}: #{e.inspect}\n")
          end
        end
      end
    end

    def log_transaction
      mode = worker_mode(worker_class)
      if mode != :disabled
        message = "#{worker_class.name} was called from inside a database transaction"
        if mode == :error
          raise SidekiqTransactionGuard::InsideTransactionError.new(message)
        else
          logger = Sidekiq.logger unless mode == :stderr
          if logger
            logger.warn(message)
          else
            $stderr.write("WARNING #{message}\n")
          end
          notify!(worker_class, job)
        end
      end
    end
  end
end
