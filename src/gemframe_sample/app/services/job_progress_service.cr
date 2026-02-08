module GemframeSample
  # Event payload models emitted by JobProgressService.
  # We keep these next to the producing service so behavior and payload shape
  # evolve together.
  Framework.serializable_record JobStartedEvent, job_id : String, source : String, message : String
  Framework.serializable_record JobProgressEvent, job_id : String, percent : Int32, delay_seconds : Float64, message : String, done : Bool
  Framework.serializable_record JobCompletedEvent, job_id : String, percent : Int32, message : String, done : Bool
  Framework.serializable_record JobErrorEvent, job_id : String, message : String, done : Bool
  Framework.serializable_record JobStartResult, job_id : String, status : String

  # Typed event declarations:
  # - define bridge emitter methods (for example @bridge.job_update(...))
  # - provide metadata for generated TypeScript types and topic maps
  module JobEvents
    extend self

    STARTED_TOPIC   = "job.started"
    PROGRESS_TOPIC  = "job.progress"
    COMPLETED_TOPIC = "job.complete"
    FAILED_TOPIC    = "job.error"

    Framework.define_typed_event(
      method_name: :job_started,
      topic: JobEvents::STARTED_TOPIC,
      payload_type: JobStartedEvent
    )
    Framework.define_typed_event(
      method_name: :job_update,
      topic: JobEvents::PROGRESS_TOPIC,
      payload_type: JobProgressEvent
    )
    Framework.define_typed_event(
      method_name: :job_completed,
      topic: JobEvents::COMPLETED_TOPIC,
      payload_type: JobCompletedEvent
    )
    Framework.define_typed_event(
      method_name: :job_failed,
      topic: JobEvents::FAILED_TOPIC,
      payload_type: JobErrorEvent
    )
  end

  # Starts demo jobs and streams progress updates back to the frontend.
  #
  # JavaScript example:
  #   import CrystalBridge from "../framework/generated/crystal_bridge";
  #   import { createFrontendBridgeRuntimeFromWindow } from "../framework/bridge_runtime.js";
  #
  #   const runtime = createFrontendBridgeRuntimeFromWindow();
  #   runtime.bus.on("job.progress", payload => console.log(payload.job_id, payload.percent));
  #   const started = await CrystalBridge.jobs.start_demo("frontend-button");
  #   console.log(started.job_id, started.status);
  class JobProgressService
    def initialize(@bridge : Bridge)
    end

    def start_demo(source : String = "frontend") : JobStartResult
      job_id = "job-#{Time.utc.to_unix_ms}-#{Random.rand(1_000_000)}"

      spawn do
        run_demo(job_id, source)
      end

      JobStartResult.new(job_id, "started")
    end

    private def run_demo(job_id : String, source : String) : Nil
      puts "Job #{job_id} started from #{source}"
      @bridge.job_started(
        JobStartedEvent.new(
          job_id: job_id,
          source: source,
          message: "Backend started demo job"
        )
      )

      (10..100).step(10) do |percent|
        delay_seconds = Random.rand(0.2..1.0)
        sleep(delay_seconds.seconds)

        puts "Job #{job_id} progress: #{percent}% (delay: #{delay_seconds.round(2)}s)"

        @bridge.job_update(
          JobProgressEvent.new(
            job_id: job_id,
            percent: percent,
            delay_seconds: delay_seconds,
            message: "Processed #{percent}%",
            done: false
          )
        )
      end

      puts "Job #{job_id} completed"

      @bridge.job_completed(
        JobCompletedEvent.new(
          job_id: job_id,
          percent: 100,
          message: "Demo job completed",
          done: true
        )
      )
    rescue ex
      @bridge.job_failed(
        JobErrorEvent.new(
          job_id: job_id,
          message: ex.message || ex.class.name,
          done: true
        )
      )
    end
  end
end
