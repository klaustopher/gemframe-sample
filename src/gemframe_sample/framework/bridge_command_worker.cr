module GemframeSample
  module Framework
    class BridgeCommandWorker
      private class Request
        @response : JSON::Any?
        @completed : Bool
        @mutex : Thread::Mutex
        @cv : Thread::ConditionVariable

        getter args : Array(JSON::Any)

        def initialize(@args : Array(JSON::Any))
          @response = nil
          @completed = false
          @mutex = Thread::Mutex.new
          @cv = Thread::ConditionVariable.new
        end

        def complete(response : JSON::Any) : Nil
          @mutex.synchronize do
            @response = response
            @completed = true
            @cv.signal
          end
        end

        def wait_response : JSON::Any
          @mutex.synchronize do
            until @completed
              @cv.wait(@mutex)
            end

            @response.not_nil!
          end
        end
      end

      @bridge : Bridge
      @queue : Deque(Request)
      @queue_mutex : Mutex
      @thread : Thread
      @closed : Atomic(Bool)

      def initialize(@bridge : Bridge)
        @queue = Deque(Request).new
        @queue_mutex = Mutex.new
        @closed = Atomic(Bool).new(false)
        @thread = Thread.new do
          run_loop
        end
      end

      def invoke(args : Array(JSON::Any)) : JSON::Any
        return shutdown_response if @closed.get

        request = Request.new(args)
        @queue_mutex.synchronize do
          return shutdown_response if @closed.get
          @queue << request
        end

        request.wait_response
      rescue ex
        TerminalLog.error("bridge command worker invoke", ex)
        internal_error_response(ex)
      end

      def shutdown : Nil
        already_closed = @closed.swap(true)
        return if already_closed

        @thread.join
      rescue ex
        TerminalLog.error("bridge command worker shutdown", ex)
      end

      private def run_loop : Nil
        loop do
          request = next_request

          unless request
            break if @closed.get

            # Keep this thread's scheduler active so fibers spawned in command
            # handlers can continue to run even when no new command arrives.
            sleep 1.millisecond
            next
          end

          response = begin
            @bridge.invoke(request.args)
          rescue ex
            TerminalLog.error("bridge command worker run_loop", ex)
            internal_error_response(ex)
          end

          request.complete(response)
        end
      rescue ex
        TerminalLog.error("bridge command worker loop", ex)
      end

      private def next_request : Request?
        @queue_mutex.synchronize do
          @queue.shift?
        end
      end

      private def internal_error_response(ex : Exception) : JSON::Any
        message = ex.message || ex.class.name
        BridgeResponse.new(false, nil, BridgeError.new("INTERNAL_ERROR", message)).to_json_any
      end

      private def shutdown_response : JSON::Any
        BridgeResponse.new(
          false,
          nil,
          BridgeError.new("SHUTDOWN", "Runtime is shutting down")
        ).to_json_any
      end
    end
  end
end
