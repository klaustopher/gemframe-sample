import { CrystalEventTopics, CrystalModels } from "./generated/crystal_bridge";
import type {
  CrystalBridgeEnvelope,
  CrystalEnvelope,
  CrystalEventTopicMap,
  CrystalKnownEventTopic,
} from "./generated/crystal_bridge";

/**
 * Raw envelope handler used by internal and public event subscriptions.
 */
type EnvelopeHandler = (envelope: CrystalBridgeEnvelope) => void;

/**
 * Topic-aware handler where payload and envelope are strongly typed from the
 * generated bridge topic map.
 */
type TypedEventHandler<TTopic extends CrystalKnownEventTopic> = (
  payload: CrystalEventTopicMap[TTopic],
  envelope: CrystalEnvelope<TTopic>
) => void;
type ModelFactory = { from(data?: Record<string, unknown>): unknown };
type BridgeInvokeError = { code?: string; message?: string } | null | undefined;
type BridgeInvokeResponse = {
  ok: boolean;
  data?: unknown;
  error?: BridgeInvokeError;
};

/**
 * Typed subscription helper attached to the runtime object.
 * Returns an unsubscribe function.
 */
export type FrontendRuntimeOn = <TTopic extends CrystalKnownEventTopic>(
  topic: TTopic,
  handler: TypedEventHandler<TTopic>
) => () => void;

/**
 * Typed unsubscription helper attached to the runtime object.
 */
export type FrontendRuntimeOff = <TTopic extends CrystalKnownEventTopic>(
  topic: TTopic,
  handler: TypedEventHandler<TTopic>
) => void;

/**
 * Shared global runtime shape stored on `window.__GEMFRAME_SAMPLE__`.
 * The Crystal backend emits into `__bridgeDispatch` and frontend code consumes
 * events through `bus`, `on`, `once`, and related helpers.
 */
export interface FrontendRuntimeState extends Record<string, unknown> {
  bus: FrontendBridgeBus;
  on: FrontendRuntimeOn;
  off: FrontendRuntimeOff;
  once: FrontendRuntimeOn;
  onAny: (handler: EnvelopeHandler) => () => void;
  onEnvelope: (topic: string, handler: EnvelopeHandler) => () => void;
  offEnvelope: (topic: string, handler: EnvelopeHandler) => void;
  _queue: unknown[];
  __bridgeDispatch: (envelope: unknown) => void;
}

/**
 * Runtime instance returned by factory functions in this module.
 */
export interface FrontendBridgeRuntime {
  runtime: FrontendRuntimeState;
  bus: FrontendBridgeBus;
  flushPendingEnvelopes: (
    dispatch?: (bus: FrontendBridgeBus, envelope: unknown) => void
  ) => void;
}

declare global {
  interface Window {
    bridgeInvoke?: (command: string, ...args: unknown[]) => BridgeInvokeResponse | Promise<BridgeInvokeResponse>;
    __GEMFRAME_SAMPLE__?: FrontendRuntimeState;
  }
}

const LIFECYCLE_INSTALLED_FLAG = "__frameworkLifecycleInstalled";
const TERMINATE_BINDING = "__gemframeTerminate";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function callTerminate(source: string): void {
  const maybeTerminate = (window as unknown as Record<string, unknown>)[TERMINATE_BINDING];
  if (typeof maybeTerminate !== "function") {
    return;
  }

  try {
    (maybeTerminate as (source: string) => unknown)(source);
  } catch (_) {
    // Ignore errors from shutdown hooks; runtime still owns process termination.
  }
}

/**
 * Builds nested command namespaces from dot-path commands.
 * Example: "math.add" -> `{ math: { add: handler } }`.
 */
function registerCommandHandler(
  commandRuntime: Record<string, unknown>,
  path: string,
  handler: unknown
): void {
  const parts = path.split(".");
  let node = commandRuntime;
  for (let i = 0; i < parts.length - 1; i += 1) {
    const key = parts[i];
    const existing = node[key];
    if (!existing || typeof existing !== "object") {
      node[key] = {};
    }
    node = node[key] as Record<string, unknown>;
  }

  node[parts[parts.length - 1]] = handler;
}

/**
 * Generic command invocation helper used by generated command wrappers.
 * Throws if bridge bindings are not installed or if backend returns an error.
 */
export async function invokeCommand(command: string, ...args: unknown[]): Promise<unknown> {
  const bridgeInvoke = window.bridgeInvoke;
  if (typeof bridgeInvoke !== "function") {
    throw new Error("bridgeInvoke binding is not available in this runtime.");
  }

  const response = await bridgeInvoke(command, ...args);
  if (!response.ok) {
    const code = response.error?.code || "UNKNOWN_ERROR";
    const message = response.error?.message || "No error details";
    throw new Error(`${code}: ${message}`);
  }

  return response.data;
}

/**
 * Creates the runtime command object used as generated `CrystalBridge`.
 * Input is a flat command map keyed by full command path.
 */
export function createCommandBridge<TBridgeModule>(
  handlersByPath: Record<string, unknown>
): TBridgeModule {
  const commandRuntime: Record<string, unknown> = {};
  for (const [path, handler] of Object.entries(handlersByPath)) {
    registerCommandHandler(commandRuntime, path, handler);
  }

  return commandRuntime as unknown as TBridgeModule;
}

/**
 * Installs window-level lifecycle and queue hooks once.
 *
 * Responsibilities:
 * - ensures a pre-runtime queue is available so backend events are not lost
 * - installs Cmd+Q and unload hooks that call backend termination binding
 * - initializes `window.__GEMFRAME_SAMPLE__` if missing
 */
export function installFrameworkWindowHooks(): FrontendRuntimeState {
  const runtimeRecord: Record<string, unknown> = isRecord(window.__GEMFRAME_SAMPLE__)
    ? (window.__GEMFRAME_SAMPLE__ as Record<string, unknown>)
    : {};

  // Events emitted before runtime bootstrap are buffered here.
  const queued = Array.isArray(runtimeRecord._queue) ? runtimeRecord._queue : [];
  runtimeRecord._queue = queued;

  if (typeof runtimeRecord.__bridgeDispatch !== "function") {
    runtimeRecord.__bridgeDispatch = (envelope: unknown) => {
      (runtimeRecord._queue as unknown[]).push(envelope);
    };
  }

  if (runtimeRecord[LIFECYCLE_INSTALLED_FLAG] !== true) {
    runtimeRecord[LIFECYCLE_INSTALLED_FLAG] = true;

    window.addEventListener("keydown", event => {
      const isMac = /Mac|iPhone|iPad|iPod/.test(navigator.platform);
      if (!isMac) {
        return;
      }

      const key = String(event.key || "").toLowerCase();
      if (event.metaKey && key === "q") {
        event.preventDefault();
        callTerminate("cmd+q");
      }
    });

    window.addEventListener("beforeunload", () => callTerminate("beforeunload"));
    window.addEventListener("pagehide", () => callTerminate("pagehide"));
  }

  window.__GEMFRAME_SAMPLE__ = runtimeRecord as FrontendRuntimeState;
  return window.__GEMFRAME_SAMPLE__;
}

/**
 * Hydrates known payloads into generated model instances (if available).
 * Unknown topics are passed through unchanged.
 */
function hydratePayload(topic: string, payload: unknown): unknown {
  const payloadType = (CrystalEventTopics as Record<string, string>)[topic];
  if (!payloadType) {
    return payload;
  }

  const model = (CrystalModels as unknown as Record<string, ModelFactory>)[payloadType];
  if (!model || typeof model.from !== "function" || !isRecord(payload)) {
    return payload;
  }

  try {
    return model.from(payload);
  } catch (_) {
    return payload;
  }
}

/**
 * Normalizes unknown raw envelope values into the bridge envelope union.
 * Returns null for invalid payloads so callers can safely ignore them.
 */
function normalizeEnvelope(rawEnvelope: unknown): CrystalBridgeEnvelope | null {
  if (!isRecord(rawEnvelope)) {
    return null;
  }

  const topic = typeof rawEnvelope.topic === "string" ? rawEnvelope.topic : "";
  if (topic.length === 0) {
    return null;
  }

  const payload = hydratePayload(topic, rawEnvelope.payload);
  return { ...rawEnvelope, topic, payload } as CrystalBridgeEnvelope;
}

/**
 * In-memory event bus used by the frontend runtime.
 * Supports typed topic subscriptions and raw envelope subscriptions.
 */
export class FrontendBridgeBus {
  private readonly topicListeners = new Map<string, Set<EnvelopeHandler>>();
  private readonly anyListeners = new Set<EnvelopeHandler>();
  private readonly typedWrappers = new Map<string, WeakMap<object, EnvelopeHandler>>();

  /**
   * Subscribes to a known topic with typed payload and envelope.
   * Returns an unsubscribe function.
   */
  on<TTopic extends CrystalKnownEventTopic>(
    topic: TTopic,
    handler: TypedEventHandler<TTopic>
  ): () => void {
    const wrapped: EnvelopeHandler = envelope => {
      if (envelope.topic !== topic) {
        return;
      }

      const knownEnvelope = envelope as CrystalEnvelope<TTopic>;
      handler(knownEnvelope.payload, knownEnvelope);
    };

    let wrappers = this.typedWrappers.get(topic);
    if (!wrappers) {
      wrappers = new WeakMap<object, EnvelopeHandler>();
      this.typedWrappers.set(topic, wrappers);
    }
    wrappers.set(handler as unknown as object, wrapped);

    return this.onEnvelope(topic, wrapped);
  }

  /**
   * Unsubscribes a typed topic handler registered via `on`.
   */
  off<TTopic extends CrystalKnownEventTopic>(
    topic: TTopic,
    handler: TypedEventHandler<TTopic>
  ): void {
    const wrappers = this.typedWrappers.get(topic);
    const wrapped = wrappers?.get(handler as unknown as object);
    if (!wrapped) {
      return;
    }

    this.offEnvelope(topic, wrapped);
    wrappers?.delete(handler as unknown as object);
  }

  /**
   * Subscribes once to a known topic.
   */
  once<TTopic extends CrystalKnownEventTopic>(
    topic: TTopic,
    handler: TypedEventHandler<TTopic>
  ): () => void {
    let unsubscribe: () => void = () => {};
    unsubscribe = this.on(topic, (payload, envelope) => {
      unsubscribe();
      handler(payload, envelope);
    });
    return unsubscribe;
  }

  /**
   * Subscribes to raw envelopes for any topic string.
   */
  onEnvelope(topic: string, handler: EnvelopeHandler): () => void {
    if (!this.topicListeners.has(topic)) {
      this.topicListeners.set(topic, new Set());
    }

    this.topicListeners.get(topic)?.add(handler);
    return () => this.offEnvelope(topic, handler);
  }

  /**
   * Unsubscribes a raw topic handler.
   */
  offEnvelope(topic: string, handler: EnvelopeHandler): void {
    const listeners = this.topicListeners.get(topic);
    if (!listeners) {
      return;
    }

    listeners.delete(handler);
    if (listeners.size === 0) {
      this.topicListeners.delete(topic);
    }
  }

  /**
   * Subscribes to every envelope regardless of topic.
   */
  onAny(handler: EnvelopeHandler): () => void {
    this.anyListeners.add(handler);
    return () => this.anyListeners.delete(handler);
  }

  /**
   * Emits an envelope to all matching listeners.
   */
  emit(envelope: CrystalBridgeEnvelope): void {
    for (const handler of this.anyListeners) {
      handler(envelope);
    }

    const listeners = this.topicListeners.get(envelope.topic);
    if (!listeners) {
      return;
    }

    for (const handler of listeners) {
      handler(envelope);
    }
  }
}

/**
 * Normalizes and dispatches a backend envelope into:
 * - the in-memory event bus
 * - DOM events (`crystal:event` and `crystal:event:<topic>`)
 */
export function dispatchBridgeEnvelopeToDom(
  bus: FrontendBridgeBus,
  rawEnvelope: unknown
): void {
  const envelope = normalizeEnvelope(rawEnvelope);
  if (!envelope) {
    return;
  }

  bus.emit(envelope);
  window.dispatchEvent(new CustomEvent<CrystalBridgeEnvelope>("crystal:event", { detail: envelope }));
  window.dispatchEvent(
    new CustomEvent<CrystalBridgeEnvelope>(`crystal:event:${envelope.topic}`, { detail: envelope })
  );
}

/**
 * Creates a frontend bridge runtime from existing state.
 *
 * This function:
 * - reuses pre-bootstrap queued envelopes
 * - installs runtime bus helpers onto shared global state
 * - defers dispatch until `flushPendingEnvelopes` is called
 */
export function createFrontendBridgeRuntime(
  existingState: unknown = undefined
): FrontendBridgeRuntime {
  const runtimeRecord: Record<string, unknown> = isRecord(existingState) ? existingState : {};
  const queued = Array.isArray(runtimeRecord._queue) ? runtimeRecord._queue : [];
  const pendingEnvelopes = [...queued];
  const bus = new FrontendBridgeBus();
  let bridgeReady = false;

  const on: FrontendRuntimeOn = (topic, handler) => bus.on(topic, handler);
  const off: FrontendRuntimeOff = (topic, handler) => bus.off(topic, handler);
  const once: FrontendRuntimeOn = (topic, handler) => bus.once(topic, handler);

  const runtime = runtimeRecord as FrontendRuntimeState;
  runtime.bus = bus;
  runtime.on = on;
  runtime.off = off;
  runtime.once = once;
  runtime.onAny = handler => bus.onAny(handler);
  runtime.onEnvelope = (topic, handler) => bus.onEnvelope(topic, handler);
  runtime.offEnvelope = (topic, handler) => bus.offEnvelope(topic, handler);
  runtime._queue = [];
  runtime.__bridgeDispatch = envelope => {
    if (!bridgeReady) {
      pendingEnvelopes.push(envelope);
      return;
    }

    dispatchBridgeEnvelopeToDom(bus, envelope);
  };

  window.__GEMFRAME_SAMPLE__ = runtime;

  return {
    runtime,
    bus,
    flushPendingEnvelopes(dispatch = dispatchBridgeEnvelopeToDom) {
      bridgeReady = true;

      while (pendingEnvelopes.length > 0) {
        const envelope = pendingEnvelopes.shift();
        dispatch(bus, envelope);
      }
    },
  };
}

/**
 * Convenience bootstrap for normal app startup.
 * Installs window hooks and then creates the typed runtime.
 */
export function createFrontendBridgeRuntimeFromWindow(): FrontendBridgeRuntime {
  installFrameworkWindowHooks();
  return createFrontendBridgeRuntime(window.__GEMFRAME_SAMPLE__);
}
