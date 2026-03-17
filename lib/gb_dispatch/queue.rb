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
      if defined?(Rails) && defined?(ActiveRecord::Base)
        require 'gb_dispatch/active_record_patch'
        thread_block = ->() do
          if Rails::VERSION::MAJOR < 5
            begin
              ActiveRecord::Base.connection_pool.force_new_connection do
                block ? block.call : yield
              end
            ensure
              ActiveRecord::Base.clear_active_connections!
            end
          else
            Rails.application.executor.wrap do
              ActiveRecord::Base.connection_pool.force_new_connection do
                block ? block.call : yield
              end
            end
          end
        end
      elsif defined?(ActiveRecord::Base)
        require 'gb_dispatch/active_record_patch'
        thread_block = ->() do
          begin
            ActiveRecord::Base.connection_pool.force_new_connection do
              block ? block.call : yield
            end
          ensure
            ActiveRecord::Base.clear_active_connections!
          end
        end
      else
        thread_block = block ? block : ->() { yield }
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
        block = ->(){ yield } unless block
        self.async.perform_now block
      end
      task.execute
      task
    end

    def to_s
      self.name.to_s
    end
  end
end
