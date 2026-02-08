import CrystalBridge from "../framework/generated/crystal_bridge";
import {
  createFrontendBridgeRuntimeFromWindow,
  dispatchBridgeEnvelopeToDom,
} from "../framework/bridge_runtime.js";
import type { CrystalBridgeEnvelope } from "../framework/generated/crystal_bridge";
import type { FrontendBridgeRuntime } from "../framework/bridge_runtime.js";

type JobStatus = "queued" | "running" | "completed" | "error";

interface JobState {
  job_id: string;
  status: JobStatus;
  percent: number;
  message: string;
  delay_seconds?: number;
  updated_at?: string;
}

function requireElement<TElement extends Element>(selector: string): TElement {
  const element = document.querySelector(selector);
  if (!element) {
    throw new Error(`Missing required element: ${selector}`);
  }

  return element as TElement;
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) {
    return error.message;
  }

  if (typeof error === "string") {
    return error;
  }

  return "Unknown error";
}

const callBridgeButton = requireElement<HTMLButtonElement>("#call-bridge");
const callGreeterButton = requireElement<HTMLButtonElement>("#call-greeter");
const jobStartButton = requireElement<HTMLButtonElement>("#job-start");
const jobClearDoneButton = requireElement<HTMLButtonElement>("#job-clear-done");
const helloResult = requireElement<HTMLPreElement>("#hello-result");
const greeterResult = requireElement<HTMLPreElement>("#greeter-result");
const mathResult = requireElement<HTMLPreElement>("#math-result");
const jobResult = requireElement<HTMLPreElement>("#job-result");
const mathAddButton = requireElement<HTMLButtonElement>("#math-add");
const mathSubtractButton = requireElement<HTMLButtonElement>("#math-subtract");
const mathMultiplyButton = requireElement<HTMLButtonElement>("#math-multiply");
const mathDivideButton = requireElement<HTMLButtonElement>("#math-divide");
const greeterNameInput = requireElement<HTMLInputElement>("#greeter-name");
const greeterTimeInput = requireElement<HTMLInputElement>("#greeter-time");
const mathLeftInput = requireElement<HTMLInputElement>("#math-left");
const mathRightInput = requireElement<HTMLInputElement>("#math-right");
const debugLog = requireElement<HTMLPreElement>("#debug-log");
const jobList = requireElement<HTMLDivElement>("#job-list");

const debugEntries: Array<Record<string, unknown>> = [];
const jobStates = new Map<string, JobState>();

function isTerminalStatus(status: JobStatus): boolean {
  return status === "completed" || status === "error";
}

function renderModuleResult(element: HTMLElement, title: string, value: unknown): void {
  element.textContent = `${title}\n\n${JSON.stringify(value, null, 2)}`;
}

function renderModuleError(
  element: HTMLElement,
  title: string,
  error: unknown,
  debugKind: string
): void {
  const message = errorMessage(error);
  renderModuleResult(element, title, { message });
  addDebug({
    kind: debugKind,
    message,
  });
}

function renderDebug(): void {
  if (debugEntries.length === 0) {
    debugLog.textContent = "No debug entries yet.";
    return;
  }

  debugLog.textContent = JSON.stringify(debugEntries, null, 2);
}

function addDebug(entry: Record<string, unknown>): void {
  const now = new Date().toISOString();
  debugEntries.push({ at: now, ...entry });
  if (debugEntries.length > 100) {
    debugEntries.shift();
  }
  renderDebug();
}

function renderJobs(): void {
  if (jobStates.size === 0) {
    jobList.textContent = "No jobs yet.";
    jobClearDoneButton.disabled = true;
    return;
  }

  const fragment = document.createDocumentFragment();
  const rows = Array.from(jobStates.values());
  const doneCount = rows.filter(row => isTerminalStatus(row.status)).length;
  jobClearDoneButton.disabled = doneCount === 0;

  for (const row of rows) {
    const item = document.createElement("article");
    item.className = "job-item";

    const title = document.createElement("p");
    title.textContent = `${row.job_id} (${row.status})`;
    item.appendChild(title);

    const message = document.createElement("p");
    message.textContent = row.message || "No message";
    item.appendChild(message);

    const progress = document.createElement("progress");
    progress.max = 100;
    progress.value = row.percent;
    item.appendChild(progress);

    const meta = document.createElement("p");
    meta.textContent = `Progress: ${row.percent}% | Updated: ${row.updated_at}`;
    item.appendChild(meta);

    fragment.appendChild(item);
  }

  jobList.replaceChildren(fragment);
}

function patchJobState(jobId: string, patch: Partial<JobState>): void {
  if (!jobId) {
    return;
  }

  const existing: JobState = jobStates.get(jobId) || {
    job_id: jobId,
    status: "queued",
    percent: 0,
    message: "Queued",
  };

  const next: JobState = {
    ...existing,
    ...patch,
    job_id: jobId,
    percent: Number(patch.percent ?? existing.percent ?? 0),
    updated_at: new Date().toISOString(),
  };

  jobStates.set(jobId, next);
  renderJobs();
}

function installBusSubscriptions(runtime: FrontendBridgeRuntime): void {
  const bus = runtime.bus;

  bus.on("job.started", payload => {
    patchJobState(payload.job_id, {
      status: "running",
      percent: 0,
      message: payload.message || "Backend started demo job",
    });
    renderModuleResult(jobResult, "job.started", payload);
    addDebug({
      kind: "job.started",
      payload,
    });
  });

  bus.on("job.progress", payload => {
    const percent = Number(payload.percent || 0);
    const delay = Number(payload.delay_seconds || 0);
    patchJobState(payload.job_id, {
      status: "running",
      percent,
      message: payload.message || `Processed ${percent}%`,
      delay_seconds: delay,
    });
    renderModuleResult(jobResult, "job.progress", payload);
    addDebug({
      kind: "job.progress",
      job_id: payload.job_id,
      percent,
      delay_seconds: delay,
    });
  });

  bus.on("job.complete", payload => {
    patchJobState(payload.job_id, {
      status: "completed",
      percent: 100,
      message: payload.message || "Completed",
    });
    renderModuleResult(jobResult, "job.complete", payload);
    addDebug({
      kind: "job.complete",
      payload,
    });
  });

  bus.on("job.error", payload => {
    patchJobState(payload.job_id, {
      status: "error",
      message: payload.message || "Unknown error",
    });
    renderModuleResult(jobResult, "job.error", payload);
    addDebug({
      kind: "job.error",
      payload,
    });
  });

  bus.onAny(envelope => {
    const record = envelope as Record<string, unknown>;
    const id = typeof record.id === "string" ? record.id : "missing-id";
    const timestamp = typeof record.timestamp === "string" ? record.timestamp : "missing-timestamp";

    addDebug({
      kind: "bus.any",
      topic: envelope.topic,
      id,
      timestamp,
    });
  });
}

function installGlobalEventListeners(): void {
  window.addEventListener("crystal:event", event => {
    const detail = (event as CustomEvent<CrystalBridgeEnvelope>).detail;
    addDebug({
      kind: "dom.event",
      event: "crystal:event",
      topic: detail?.topic || "unknown",
    });
  });
}

function readMathInputs(): { left: number; right: number } {
  const left = Number.parseFloat(mathLeftInput.value);
  const right = Number.parseFloat(mathRightInput.value);

  if (!Number.isFinite(left) || !Number.isFinite(right)) {
    throw new Error("Math inputs must be valid numbers");
  }

  return { left, right };
}

type MathOperation = keyof typeof CrystalBridge.math;

function bindMathOperation(button: HTMLButtonElement, operation: MathOperation): void {
  button.addEventListener("click", async () => {
    try {
      const { left, right } = readMathInputs();
      const data = await CrystalBridge.math[operation](left, right);
      renderModuleResult(mathResult, `math.${operation}`, data);
    } catch (error: unknown) {
      renderModuleError(
        mathResult,
        `math.${operation} error`,
        error,
        `math.${operation}.error`
      );
    }
  });
}

async function boot(): Promise<void> {
  try {
    greeterTimeInput.value = new Date().toISOString();
    renderJobs();

    const runtime: FrontendBridgeRuntime = createFrontendBridgeRuntimeFromWindow();
    installBusSubscriptions(runtime);
    installGlobalEventListeners();
    runtime.flushPendingEnvelopes(dispatchBridgeEnvelopeToDom);

    const info = await CrystalBridge.runtime.info();
    renderModuleResult(helloResult, "runtime.info", info);
    addDebug({
      kind: "startup",
      message: "runtime.info loaded",
    });
  } catch (error: unknown) {
    renderModuleError(helloResult, "runtime.info error", error, "startup.error");
  }
}

callBridgeButton.addEventListener("click", async () => {
  try {
    const data = await CrystalBridge.hello("Klaus");
    renderModuleResult(helloResult, "hello", data);
  } catch (error: unknown) {
    renderModuleError(helloResult, "hello error", error, "hello.error");
  }
});

callGreeterButton.addEventListener("click", async () => {
  try {
    const data = await CrystalBridge.greeter.greet(
      greeterNameInput.value || "World",
      greeterTimeInput.value || new Date().toISOString()
    );
    renderModuleResult(greeterResult, "greeter.greet", data);
  } catch (error: unknown) {
    renderModuleError(greeterResult, "greeter.greet error", error, "greeter.error");
  }
});

jobStartButton.addEventListener("click", async () => {
  try {
    const data = await CrystalBridge.jobs.start_demo("frontend-button");
    patchJobState(data.job_id, {
      status: "queued",
      percent: 0,
      message: "Requested from frontend",
    });
    renderModuleResult(jobResult, "jobs.start_demo", data);
    addDebug({
      kind: "job.command.start_demo",
      payload: data,
    });
  } catch (error: unknown) {
    renderModuleError(jobResult, "jobs.start_demo error", error, "job.command.error");
  }
});

jobClearDoneButton.addEventListener("click", () => {
  for (const [jobId, state] of jobStates.entries()) {
    if (isTerminalStatus(state.status)) {
      jobStates.delete(jobId);
    }
  }

  renderJobs();
});

bindMathOperation(mathAddButton, "add");
bindMathOperation(mathSubtractButton, "subtract");
bindMathOperation(mathMultiplyButton, "multiply");
bindMathOperation(mathDivideButton, "divide");

boot();
