require 'concurrent'
module GBDispatch
  class Queue
    include Concurrent::Async

    # @return [String] queue name
    attr_reader :name

    # @param name [String] queue name, should be the same as is register in Celluloid
    def initialize(name)
      super()
      @name = name
    end

    # Perform given block
    #
    # If used with rails it will wrap block with connection pool.
    # @param block [Proc]
    # @yield if there is no block given it yield without param.
    # @return [Object, Exception] returns value of executed block or exception if block execution failed.
    def perform_now(block=nil)
      Thread.current[:name] ||= name
      thread_block = ->() do
        with_rails_executor do
          with_connection_pool do
            block ? block.call : yield
          end
        end
      end
      begin
        Runner.execute thread_block, name: name
      rescue Exception => e
        return e
      end
    end

    # Perform block after given period
    # @param time [Fixnum]
    # @param block [Proc]
    # @yield if there is no block given it yield without param.
    # @return [Concurrent::ScheduledTask]
    def perform_after(time, block=nil)
      task = Concurrent::ScheduledTask.new(time) do
        self.async.perform_now do
          block ? block.call : yield
        end
      end
      task.execute
      task
    end

    def to_s
      self.name.to_s
    end

    private

    def with_connection_pool
      return yield unless defined?(ActiveRecord::Base)

      require 'gb_dispatch/active_record_patch'
      # `force_new_connection` is a monkey-patch in active_record_patch.rb
      # that keeps background-thread connection handling safe across Rails
      # versions:
      #
      # * On Rails 7.2+ with `@pinned_connection` (`use_transactional_fixtures`),
      #   it serializes access to the pinned connection via its per-connection
      #   mutex so worker and caller threads can't race on the same pg socket.
      # * On Rails 7.1 with `@lock_thread`, it nils the lock so the worker
      #   gets a fresh connection instead of inheriting the caller's cached one.
      # * Otherwise (production, older AR, non-Rails), it delegates to
      #   plain `with_connection`.
      ActiveRecord::Base.connection_pool.force_new_connection do
        yield
      end
    end

    def with_rails_executor
      return yield unless defined?(Rails) && Rails::VERSION::MAJOR >= 5

      Rails.application.executor.wrap do
        yield
      end
    end
  end
end
