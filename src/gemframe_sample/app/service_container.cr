module GemframeSample
  # Small application-level container.
  # This is where we wire concrete services for the sample app without leaking
  # framework setup details into individual service classes.
  class ServiceContainer
    getter runtime_service : RuntimeService
    getter hello_service : HelloService
    getter job_progress_service : JobProgressService
    getter greeter : GreeterService
    getter math : MathService

    def initialize(bridge : Bridge)
      # App services are plain Crystal objects; only services that publish
      # frontend events need access to Bridge.
      @runtime_service = RuntimeService.new
      @hello_service = HelloService.new
      @job_progress_service = JobProgressService.new(bridge)
      @greeter = GreeterService.new
      @math = MathService.new
    end

    def shutdown : Nil
      # Placeholder for graceful shutdown once services hold resources (DB pools, queues, etc).
    end
  end
end
