# GemframeSample

`GemframeSample` is a demo/prototype of **Gemframe**, a Crystal desktop app framework inspired by Tauri and Wails.

It demonstrates the target development model:

- Crystal backend services
- Webview frontend
- Vite development flow
- Typed frontend/backend bridge generated from Crystal definitions

## What To Focus On

Two parts of this repo have different purposes:

- `src/gemframe_sample/framework/` and `frontend/src/framework/`:
  - prototype framework internals
  - useful for validating ideas, not a finalized API surface
- `src/gemframe_sample/app/` and `frontend/src/app/`:
  - the important example for framework users
  - shows the style we want app code to have once the framework matures

In short: do not over-analyze framework internals yet; treat the app layer as the reference for intended user experience.

## What This Demo Proves

- App code can register backend methods via typed macros (no manual JSON plumbing in app services).
- App services can emit typed events to frontend.
- TypeScript bridge bindings are generated from Crystal command/event/type metadata.
- Runtime can own webview + Vite lifecycle while app code stays focused on domain behavior.

## Source Layout

- Crystal entrypoint: `src/gemframe_sample.cr`
- Crystal app code: `src/gemframe_sample/app/`
- Crystal framework prototype: `src/gemframe_sample/framework/`
- Frontend app code: `frontend/src/app/`
- Frontend framework runtime: `frontend/src/framework/`
- Generated frontend bridge: `frontend/src/framework/generated/crystal_bridge.ts`

## Run The Sample

From `crystal-tauri/gemframe-sample`:

```bash
shards install
crystal run src/gemframe_sample.cr
```

Default behavior:

1. Registers typed commands/events.
2. Regenerates bridge bindings.
3. Starts Vite from the Crystal runtime (if enabled).
4. Forwards Vite output to terminal.
5. Opens webview and navigates to the frontend URL.
6. Stops background processes on exit.

## Environment Variables

- `GEMFRAME_SAMPLE_FRONTEND_URL` default: `http://127.0.0.1:5173`
- `GEMFRAME_SAMPLE_VITE_HOST` default: `127.0.0.1`
- `GEMFRAME_SAMPLE_VITE_PORT` default: `5173`
- `GEMFRAME_SAMPLE_DEBUG` default: `1`
- `GEMFRAME_SAMPLE_MANAGE_VITE` default: `1` (`0` to run Vite externally)

## External Vite Mode (Optional)

Terminal 1:

```bash
cd frontend
npm install
npm run dev
```

Terminal 2:

```bash
GEMFRAME_SAMPLE_MANAGE_VITE=0 \
GEMFRAME_SAMPLE_FRONTEND_URL=http://127.0.0.1:5173 \
crystal run src/gemframe_sample.cr
```

## App Authoring Pattern (Target DX)

Application wiring stays small and explicit in `src/gemframe_sample/app/application.cr`:

```crystal
runtime.run do |bridge|
  container = ServiceContainer.new(bridge)

  Framework.register_typed_method_command(
    bridge: bridge,
    object: container.greeter,
    methods: :greet,
    prefix: "greeter"
  )
end
```

Typed backend event declaration/emission example in `src/gemframe_sample/app/services/job_progress_service.cr`:

```crystal
Framework.define_typed_event(
  method_name: :job_update,
  topic: "job.progress",
  payload_type: JobProgressEvent
)

@bridge.job_update(JobProgressEvent.new(...))
```

Frontend usage example in `frontend/src/app/main.ts`:

```ts
const started = await CrystalBridge.jobs.start_demo("frontend-button");
runtime.bus.on("job.progress", payload => {
  console.log(payload.job_id, payload.percent);
});
```

## Typed Generation Pipeline

This sample uses Crystal macros so app code declares types once and the framework derives bridge metadata from that.

### 1) Define serializable DTOs/events in Crystal

Use `Framework.serializable_record` in app services:

```crystal
Framework.serializable_record JobProgressEvent,
  job_id : String,
  percent : Int32,
  delay_seconds : Float64,
  message : String,
  done : Bool
```

`serializable_record` expands to:

- a `record` with typed fields
- `include JSON::Serializable`

So the same Crystal type is both:

- your backend domain/event DTO
- the JSON shape source for bridge type generation

### 2) Register commands from typed method signatures

Use `Framework.register_typed_method_command(...)`:

```crystal
Framework.register_typed_method_command(
  bridge: bridge,
  object: container.math,
  methods: { :add, :subtract, :multiply, :divide },
  prefix: "math"
)
```

`prefix` behavior:

- method names are always appended to `prefix`
- no `prefix` means methods are registered at the root namespace
- examples:
  - `prefix: "greeter", methods: :greet` -> `greeter.greet`
  - `methods: :hello` -> `hello`

The macro derives command metadata from the typed method signatures on `object`:

- argument names
- argument types
- required vs optional args
- return type

Then it registers the command handler and auto-converts JSON args to typed Crystal values.

Type inference for `object` currently supports:

- typed def args (for example `container : ServiceContainer`)
- zero-arg accessor calls on typed receivers (for example `container.greeter`)
- explicit casts (for example `something.as(MyService)`)

### 3) Declare typed events once and get bridge helper methods

Use `Framework.define_typed_event(...)`:

```crystal
Framework.define_typed_event(
  method_name: :job_update,
  topic: "job.progress",
  payload_type: JobProgressEvent
)
```

This does two things:

- generates a typed helper on `Bridge`:
  - `@bridge.job_update(payload : JobProgressEvent)`
- stores event signature metadata for runtime registration + TypeScript generation

So app code emits events with typed payloads and no stringly-typed JSON building:

```crystal
@bridge.job_update(
  JobProgressEvent.new(
    job_id: job_id,
    percent: percent,
    delay_seconds: delay_seconds,
    message: "Processed #{percent}%",
    done: false
  )
)
```

### 4) Runtime registers + generates frontend bridge

During startup, runtime calls:

- `Framework.register_all_typed_event_signatures(bridge: bridge)`
- `Framework::BridgeBindingsGenerator.generate!(bridge)`

This keeps runtime registrations and generated frontend types in sync from the same Crystal source data.

## What Frontend Gets Generated

Generated file: `frontend/src/framework/generated/crystal_bridge.ts`

It includes:

- typed command bridge module (`CrystalBridge`)
- interfaces for DTOs/events derived from Crystal types
- model constructors in `CrystalModels`
- typed event topic map (`CrystalEventTopicMap`)
- typed envelope unions (`CrystalEnvelope`, `CrystalBridgeEnvelope`)

Runtime helper file: `frontend/src/framework/bridge_runtime.ts`

It provides stable, non-generated plumbing:

- command invocation (`invokeCommand`)
- command namespace assembly (`createCommandBridge`)
- typed event bus/subscription runtime
- lifecycle/window hook utilities

This split is intentional:

- generated file changes with app API/types
- runtime helper stays stable framework code

## Current Scope vs Future Framework

This sample is intentionally pragmatic:

- it proves architecture and ergonomics
- it is not a production-grade framework release
- framework internals will likely change
- the app layer shape is the part we intend to preserve
