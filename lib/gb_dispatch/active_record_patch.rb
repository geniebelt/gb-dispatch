if defined?(ActiveRecord)
  module ActiveRecord
    module ConnectionAdapters
      class ConnectionPool
        # Run the given block with a connection that is safe to use from a
        # background worker thread even when the caller thread has pinned the
        # pool (`use_transactional_fixtures`).
        #
        # Rails' pool changed shape across versions, so this monkey-patch
        # has three branches:
        #
        # * Rails 7.2+ with `@pinned_connection` set. The pool forces every
        #   caller onto one shared connection during a pinned test. We can't
        #   hand out a different one without breaking the test's transaction
        #   visibility, so instead we share the pinned connection while
        #   serializing access via its per-connection `Mutex` (`.lock`). This
        #   is what prevents the `PG::UnableToSend: another command is already
        #   in progress` / `message type 0x5a arrived from server while idle`
        #   wire-protocol corruption when the worker thread interleaves with
        #   the test thread.
        # * Rails 7.1 with `@lock_thread` defined. `with_connection` hands back
        #   the caller thread's thread-cached connection; nilling `@lock_thread`
        #   temporarily lets us get a fresh one from the pool instead.
        # * Anything else (production without pinning, older AR, non-Rails
        #   embedding). `with_connection` already yields a thread-local
        #   connection from the pool; we just delegate.
        def force_new_connection
          if instance_variable_defined?(:@pinned_connection) && @pinned_connection
            @pinned_connection.lock.synchronize do
              yield @pinned_connection
            end
          elsif instance_variable_defined?(:@lock_thread)
            old_lock = @lock_thread
            @lock_thread = nil
            begin
              with_connection do |conn|
                yield conn
              end
            ensure
              @lock_thread = old_lock
            end
          else
            with_connection do |conn|
              yield conn
            end
          end
        end
      end
    end
  end
end
