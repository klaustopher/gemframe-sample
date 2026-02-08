module GemframeSample
  module Framework
    class Runtime
      def initialize(
        @title : String,
        @width : Int32,
        @height : Int32,
        @frontend_url : String,
        @debug : Bool,
        @manage_vite : Bool = false,
        @frontend_dir : String = "",
        @vite_host : String = "127.0.0.1",
        @vite_port : Int32 = 5173
      )
      end

      def run(&register_commands : Bridge -> Nil) : Nil
        Webview.with_window(
          @width,
          @height,
          Webview::SizeHints::NONE,
          @title,
          @debug
        ) do |wv|
          shutdown_requested = Atomic(Bool).new(false)
          bridge = build_bridge(wv)
          command_worker = BridgeCommandWorker.new(bridge)
          vite_server : ViteDevServer? = nil

          register_commands.call(bridge)
          Framework.register_all_typed_event_signatures(bridge: bridge)
          Framework::BridgeBindingsGenerator.generate!(bridge)

          if @manage_vite
            vite_server = ViteDevServer.new(@frontend_dir, @frontend_url, @vite_host, @vite_port)
            vite_server.start
          end

          wv.navigate(@frontend_url)
          bind_bridge(wv, command_worker)
          bind_shutdown(wv, shutdown_requested)

          begin
            wv.run
          ensure
            vite_server.try &.stop
            command_worker.shutdown
            request_shutdown(wv, shutdown_requested, "ensure")
          end
        end
      end

      private def build_bridge(wv) : Bridge
        Bridge.new(->(js : String) do
          wv.dispatch do
            wv.eval(js)
          end
        end)
      end

      private def bind_bridge(wv, command_worker : BridgeCommandWorker) : Nil
        wv.bind("bridgeInvoke", Webview::JSProc.new { |args|
          command_worker.invoke(args)
        })
      end

      private def bind_shutdown(wv, shutdown_requested : Atomic(Bool)) : Nil
        wv.bind("__gemframeTerminate", Webview::JSProc.new { |args|
          source = args[0]?.try(&.as_s?) || "frontend"
          request_shutdown(wv, shutdown_requested, source)

          JSON::Any.new({
            "ok"     => JSON::Any.new(true),
            "source" => JSON::Any.new(source),
          })
        })
      end

      private def request_shutdown(wv, shutdown_requested : Atomic(Bool), source : String) : Nil
        already_requested = shutdown_requested.swap(true)
        return if already_requested

        TerminalLog.bridge(
          "lifecycle",
          "shutdown",
          JSON::Any.new({"source" => JSON::Any.new(source)})
        )

        begin
          wv.terminate
        rescue ex
          TerminalLog.error("webview terminate", ex)
        end
      end
    end
  end
end
