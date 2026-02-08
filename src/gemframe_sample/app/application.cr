module GemframeSample
  # Application composition root.
  # Keep framework wiring (runtime + bridge command registration) in one place
  # so the rest of the app stays focused on domain logic.
  class App
    TITLE  = "GemframeSample"
    WIDTH  = 1024
    HEIGHT =  720

    def self.run : Nil
      debug = ENV["GEMFRAME_SAMPLE_DEBUG"]? != "0"
      container : ServiceContainer? = nil

      # Runtime owns the webview + bridge lifecycle.
      # App only provides app-specific options and a command-registration block.
      runtime = Framework::Runtime.new(
        title: TITLE,
        width: WIDTH,
        height: HEIGHT,
        frontend_url: FRONTEND_URL,
        debug: debug,
        manage_vite: MANAGE_VITE,
        frontend_dir: FRONTEND_DIR,
        vite_host: VITE_HOST,
        vite_port: VITE_PORT
      )

      runtime.run do |bridge|
        # Container owns app service instances and their dependencies.
        container = ServiceContainer.new(bridge)
        register_commands(bridge: bridge, container: container.not_nil!)
      end
    ensure
      container.try &.shutdown
    end

    def self.register_commands(bridge : Bridge, container : ServiceContainer) : Nil
      # Explicit app API surface exposed to JavaScript.
      # We intentionally keep these registrations centralized for discoverability.
      Framework.register_typed_method_command(
        bridge: bridge,
        object: container.runtime_service,
        methods: :info,
        prefix: "runtime"
      )
      Framework.register_typed_method_command(
        bridge: bridge,
        object: container.hello_service,
        methods: :hello
      )
      Framework.register_typed_method_command(
        bridge: bridge,
        object: container.job_progress_service,
        methods: :start_demo,
        prefix: "jobs"
      )
      Framework.register_typed_method_command(
        bridge: bridge,
        object: container.greeter,
        methods: :greet,
        prefix: "greeter"
      )
      Framework.register_typed_method_command(
        bridge: bridge,
        object: container.math,
        methods: {
          :add,
          :subtract,
          :multiply,
          :divide,
        },
        prefix: "math"
      )
    end
  end
end
