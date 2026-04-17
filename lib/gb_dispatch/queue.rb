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
      # `force_new_connection` (monkey-patch in active_record_patch.rb) temporarily
      # nils `@lock_thread` on the pool so a background worker thread gets its
      # own connection instead of inheriting the caller thread's cached one.
      # Plain `with_connection` respects the lock, which under Rails
      # `use_transactional_fixtures` hands the worker the test thread's
      # in-transaction connection via `@thread_cached_conns`; both threads then
      # race on the same Postgres socket and produce
      # `PG::UnableToSend: another command is already in progress`.
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
