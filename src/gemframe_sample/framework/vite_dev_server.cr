require "http/client"
require "file_utils"
require "uri"

module GemframeSample
  module Framework
    class ViteDevServer
      STARTUP_TIMEOUT = 45.seconds

      @frontend_dir : String
      @frontend_url : String
      @host : String
      @port : Int32
      @process : Process?

      def initialize(
        @frontend_dir : String,
        @frontend_url : String,
        @host : String,
        @port : Int32
      )
        @process = nil
      end

      def start : Nil
        return if @process

        install_deps_if_needed
        command, args = build_vite_command

        TerminalLog.bridge(
          "devserver",
          "start",
          JSON::Any.new({
            "command" => JSON::Any.new(([command] + args).join(" ")),
            "cwd"     => JSON::Any.new(@frontend_dir),
          })
        )

        @process = Process.new(
          command,
          args,
          chdir: @frontend_dir,
          output: Process::Redirect::Inherit,
          error: Process::Redirect::Inherit
        )
        wait_until_ready
      rescue ex
        stop
        raise ex
      end

      def stop : Nil
        process = @process
        @process = nil
        return unless process

        begin
          process.terminate
          wait_for_termination(process, 3.seconds)
        rescue ex
          TerminalLog.error("vite terminate", ex)
        end

        return if process.terminated?

        begin
          process.signal(Signal::KILL)
          wait_for_termination(process, 2.seconds)
        rescue ex
          TerminalLog.error("vite kill", ex)
        end
      end

      private def install_deps_if_needed : Nil
        node_modules = File.join(@frontend_dir, "node_modules")
        return if Dir.exists?(node_modules)

        TerminalLog.bridge(
          "devserver",
          "npm.install",
          JSON::Any.new({"cwd" => JSON::Any.new(@frontend_dir)})
        )

        status = Process.run(
          "npm",
          ["install"],
          chdir: @frontend_dir,
          output: Process::Redirect::Inherit,
          error: Process::Redirect::Inherit
        )
        unless status.success?
          raise "npm install failed with exit status #{status.exit_code}"
        end
      end

      private def build_vite_command : Tuple(String, Array(String))
        vite_bin = File.join(@frontend_dir, "node_modules", ".bin", "vite")
        args = ["--host", @host, "--port", @port.to_s, "--strictPort"]

        if File.exists?(vite_bin)
          {vite_bin, args}
        else
          {"npm", ["run", "dev", "--"] + args}
        end
      end

      private def wait_until_ready : Nil
        deadline = Time.instant + STARTUP_TIMEOUT

        loop do
          process = @process
          raise "Vite process missing" unless process

          if frontend_ready?
            TerminalLog.bridge(
              "devserver",
              "ready",
              JSON::Any.new({"url" => JSON::Any.new(@frontend_url)})
            )
            return
          end

          if process.terminated?
            status = process.wait
            raise "Vite exited before readiness (status #{status.exit_code})"
          end

          break if Time.instant >= deadline
          sleep 200.milliseconds
        end

        raise "Vite did not become ready at #{@frontend_url} within #{STARTUP_TIMEOUT.total_seconds}s"
      end

      private def wait_for_termination(process : Process, timeout : Time::Span) : Nil
        deadline = Time.instant + timeout
        until process.terminated? || Time.instant >= deadline
          sleep 100.milliseconds
        end
        process.wait if process.terminated?
      end

      private def frontend_ready? : Bool
        response = HTTP::Client.get(@frontend_url)
        response.success? || response.status_code < 500
      rescue
        false
      end
    end
  end
end
