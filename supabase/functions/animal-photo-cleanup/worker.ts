import { HttpTransport } from "./adapters/http.ts";
import type { Fetch } from "./adapters/http.ts";
import { JobsAdapter } from "./adapters/jobs_adapter.ts";
import { StorageAdapter } from "./adapters/storage_adapter.ts";
import { leaseBudget } from "./adapters/timeout.ts";
import { cleanup } from "./cleanup.ts";
import { classifyError } from "./errors.ts";
import type { WorkerConfig } from "./config.ts";
import type { CleanupResult } from "./types.ts";

export interface Summary {
  discovered: number;
  claimed: number;
  processed: number;
  observedEmpty: number;
  retry: number;
  quarantined: number;
  leaseExpiry: number;
  ackRejected: number;
  ackUncertain: number;
  fatal: boolean;
  interventionRequired: boolean;
  stopped:
    | "complete"
    | "deadline"
    | "error"
    | "admin"
    | "ack"
    | "lease_expiry"
    | "duplicate";
}
export type SafeLog = (
  event: Readonly<Record<string, string | number | boolean>>,
) => void;
export interface WorkerDependencies {
  fetch: Fetch;
  now: () => number;
  log?: SafeLog;
}
/** Internal, called only after handler config/auth. No global state or global mutex. */
export async function runWorker(
  config: WorkerConfig,
  deps: WorkerDependencies,
): Promise<Summary> {
  const started = deps.now(), deadline = started + config.invocationMs;
  const invocationId = crypto.randomUUID();
  const summary: Summary = {
    discovered: 0,
    claimed: 0,
    processed: 0,
    observedEmpty: 0,
    retry: 0,
    quarantined: 0,
    leaseExpiry: 0,
    ackRejected: 0,
    ackUncertain: 0,
    fatal: false,
    interventionRequired: false,
    stopped: "complete",
  };
  const emit = (fields: Record<string, string | number | boolean>) => {
    try {
      deps.log?.(Object.freeze({ invocationId, ...fields }));
    } catch { /* Logging cannot affect ACKs. */ }
  };
  const http = new HttpTransport(
    config.url,
    { apikey: config.secret },
    deps.fetch,
    deps.now,
  );
  let requestDeadline = () =>
    Math.min(deadline - config.skewMs, deps.now() + config.requestMs);
  const jobs = new JobsAdapter(http, () => requestDeadline());
  const fatal = () => {
    if (!http.fatalWorkerError) return false;
    summary.fatal = true;
    summary.stopped = "admin";
    return true;
  };
  const enough = () =>
    deadline - deps.now() > config.requestMs + config.finishMs + config.skewMs;
  const seen = new Set<string>();
  try {
    if (!enough()) {
      summary.stopped = "deadline";
      return summary;
    }
    const discovery = await jobs.discover(config.discoveryLimit);
    if (fatal()) return summary;
    if (!discovery.ok) {
      summary.stopped = "error";
      emit({ stage: "discovery", errorCode: classifyError(discovery.error) });
      return summary;
    }
    summary.discovered = discovery.value;
    for (let i = 0; i < config.maxJobs; i++) {
      if (fatal()) break;
      if (!enough()) {
        summary.stopped = "deadline";
        break;
      }
      requestDeadline = () =>
        Math.min(deadline - config.skewMs, deps.now() + config.requestMs);
      const claimed = await jobs.claim();
      if (fatal()) break;
      if (!claimed.ok) {
        summary.stopped = "error";
        emit({ stage: "claim", errorCode: classifyError(claimed.error) });
        break;
      }
      if (claimed.value === null) break;
      const job = claimed.value;
      summary.claimed++;
      if (seen.has(job.animalId)) {
        summary.leaseExpiry++;
        summary.stopped = "duplicate";
        break;
      }
      seen.add(job.animalId);
      const timing = leaseBudget(
        job.leaseExpiresAt,
        deadline,
        deps.now,
        config.requestMs,
        config.finishMs,
        config.skewMs,
      );
      if (!timing.budget.canStartList()) {
        summary.leaseExpiry++;
        summary.stopped = "deadline";
        break;
      }
      requestDeadline = timing.storageDeadline;
      const terminal = await jobs.getTerminalEvidence(job);
      if (fatal()) break;
      let result: CleanupResult;
      if (!terminal.ok) {
        result = "terminalMismatch" in terminal
          ? { outcome: "quarantined", errorCode: "terminal_mismatch" }
          : { outcome: "retry", errorCode: classifyError(terminal.error) };
      } else {
        result = await cleanup(
          job,
          terminal.value,
          new StorageAdapter(http, job, timing.storageDeadline),
          timing.budget,
          config.maxBatches,
        );
      }
      summary.processed++;
      if (fatal()) break;
      if (
        result.outcome === "retry" && result.errorCode === "budget_exhausted"
      ) {
        summary.leaseExpiry++;
        summary.stopped = "lease_expiry";
        emit({
          sequence: job.tombstoneSequence.toString(),
          generation: job.generation.toString(),
          outcome: "lease_expiry",
          errorCode: "budget_exhausted",
        });
        break; // Deliberately NO finish, including no adapter finish call.
      }
      const mismatch = result.outcome === "quarantined" &&
        result.errorCode === "terminal_mismatch";
      if (!timing.budget.canFinish()) {
        summary.leaseExpiry++;
        summary.stopped = "deadline";
        if (mismatch) summary.interventionRequired = true;
        break;
      }
      requestDeadline = timing.finishDeadline;
      const ack = await jobs.finish(job, result);
      // Retain ACK uncertainty even when an administrative failure caused it.
      if (ack.state === "uncertain") summary.ackUncertain++;
      if (mismatch && ack.state !== "accepted") {
        summary.interventionRequired = true;
      }
      if (fatal()) break;
      emit({
        sequence: job.tombstoneSequence.toString(),
        generation: job.generation.toString(),
        outcome: result.outcome,
        ack: ack.state,
        ...(result.outcome === "observed_empty"
          ? {}
          : { errorCode: result.errorCode }),
      });
      if (ack.state === "accepted") {
        // Counts mean confirmed ACK class, not guessed durable quarantine state.
        if (result.outcome === "observed_empty") summary.observedEmpty++;
        else if (result.outcome === "retry") summary.retry++;
        else summary.quarantined++;
      } else {
        if (ack.state === "rejected") summary.ackRejected++;
        if (ack.state === "not_sent" || ack.state === "lease_expiry") {
          summary.leaseExpiry++;
        }
        summary.stopped = "ack";
        break; // No re-claim after uncertain/stale ACK in this invocation.
      }
    }
  } catch {
    summary.stopped = "error";
    summary.interventionRequired = true;
    emit({ stage: "worker", errorCode: "internal_error" });
  } finally {
    emit({
      ...summary,
      durationMs: Math.max(0, Math.floor(deps.now() - started)),
    });
  }
  return summary;
}
