import { deriveNamespace } from "../namespace.ts";
import { compareTerminal, validJobMetadata } from "../terminal.ts";
import type {
  AdapterResult,
  CleanupJob,
  CleanupResult,
  TerminalRecord,
} from "../types.ts";
import { HttpTransport, malformed, record } from "./http.ts";

function integer(v: unknown): bigint | null {
  if (typeof v !== "string" || !/^[1-9]\d{0,18}(?![\s\S])/.test(v)) return null;
  const n = BigInt(v);
  return n <= 9223372036854775807n ? n : null;
}
export type FinishPlan =
  | { action: "expire_lease" }
  | {
    action: "finish";
    outcome: "observed_empty" | "retry" | "quarantined";
    errorCode: string | null;
  };
export function finishPlan(result: CleanupResult): FinishPlan {
  if (result.outcome === "observed_empty") {
    return { action: "finish", outcome: "observed_empty", errorCode: null };
  }
  if (result.outcome === "retry" && result.errorCode === "budget_exhausted") {
    return { action: "expire_lease" };
  }
  const allowed = result.outcome === "retry"
    ? [
      "storage_unavailable",
      "rate_limited",
      "timeout",
      "internal_error",
      "permission_denied",
      "no_progress",
    ]
    : ["terminal_mismatch", "invalid_namespace", "legacy_conflict"];
  if (!allowed.includes(result.errorCode)) {
    throw new Error("INVALID_FINISH_RESULT");
  }
  return {
    action: "finish",
    outcome: result.outcome,
    errorCode: result.errorCode,
  };
}
export type FinishReply = {
  state: "accepted" | "rejected" | "uncertain" | "not_sent" | "lease_expiry";
};
export type TerminalReply = AdapterResult<TerminalRecord> | {
  ok: false;
  terminalMismatch: true;
};

export class JobsAdapter {
  readonly #http: HttpTransport;
  readonly #deadline: () => number;
  // Identity provenance within this invocation: arbitrary caller-created jobs rejected.
  readonly #claims = new WeakSet<CleanupJob>();
  constructor(http: HttpTransport, deadline: () => number) {
    this.#http = http;
    this.#deadline = deadline;
  }
  get fatalWorkerError(): boolean {
    return this.#http.fatalWorkerError;
  }
  async discover(limit: number): Promise<AdapterResult<number>> {
    if (!Number.isInteger(limit) || limit < 1 || limit > 5000) {
      return malformed();
    }
    const r = await this.#http.request(
      "/rest/v1/rpc/discover_animal_photo_cleanup_jobs",
      "POST",
      { p_limit: limit },
      this.#deadline(),
    );
    if (!r.ok) return r;
    if (
      typeof r.value !== "string" ||
      !/^(0|[1-9]\d{0,3})(?![\s\S])/.test(r.value)
    ) return malformed();
    const count = Number(r.value); // SQL integer count, bounded independently of bigint identity
    return count <= limit ? { ok: true, value: count } : malformed();
  }
  async claim(): Promise<AdapterResult<CleanupJob | null>> {
    const r = await this.#http.request(
      "/rest/v1/rpc/claim_animal_photo_cleanup_job",
      "POST",
      {},
      this.#deadline(),
    );
    if (!r.ok) return r;
    if (!Array.isArray(r.value) || r.value.length > 1) return malformed();
    if (!r.value.length) return { ok: true, value: null };
    const v = r.value[0];
    if (!record(v) || v.status !== "leased") return malformed();
    const sequence = integer(v.tombstone_sequence),
      generation = integer(v.generation);
    const fields = [
      v.animal_id,
      v.user_id,
      v.tombstone_operation_id,
      v.tombstone_deleted_at,
      v.lease_token,
      v.lease_expires_at,
    ];
    if (
      sequence === null || generation === null ||
      fields.some((f) => typeof f !== "string")
    ) return malformed();
    const job: CleanupJob = Object.freeze({
      animalId: v.animal_id as string,
      userId: v.user_id as string,
      tombstoneSequence: sequence,
      generation,
      operationId: v.tombstone_operation_id as string,
      deletedAt: v.tombstone_deleted_at as string,
      leaseToken: v.lease_token as string,
      leaseExpiresAt: v.lease_expires_at as string,
    });
    if (!deriveNamespace(job) || !validJobMetadata(job)) return malformed();
    this.#claims.add(job);
    return { ok: true, value: job };
  }
  async getTerminalEvidence(job: CleanupJob): Promise<TerminalReply> {
    if (!this.#claims.has(job)) return malformed();
    const query = new URLSearchParams({
      select: "collection,entity_id,user_id,sequence,operation_id,deleted_at",
      collection: "eq.animals",
      entity_id: `eq.${job.animalId}`,
      user_id: `eq.${job.userId}`,
      limit: "2",
    });
    const r = await this.#http.request(
      `/rest/v1/sync_deletions?${query}`,
      "GET",
      undefined,
      this.#deadline(),
    );
    if (!r.ok) return r;
    if (!Array.isArray(r.value) || r.value.length > 1) return malformed();
    const v = r.value[0];
    if (v === undefined) return { ok: false, terminalMismatch: true };
    if (!record(v)) return malformed();
    const sequence = integer(v.sequence);
    if (
      sequence === null ||
      [v.collection, v.entity_id, v.user_id, v.operation_id, v.deleted_at].some(
        (f) => typeof f !== "string",
      )
    ) return malformed();
    const terminal: TerminalRecord = Object.freeze({
      collection: v.collection as string,
      entityId: v.entity_id as string,
      userId: v.user_id as string,
      sequence,
      operationId: v.operation_id as string,
      deletedAt: v.deleted_at as string,
    });
    return compareTerminal(job, terminal)
      ? { ok: false, terminalMismatch: true }
      : { ok: true, value: terminal };
  }
  async finish(job: CleanupJob, result: CleanupResult): Promise<FinishReply> {
    if (!this.#claims.has(job) || this.fatalWorkerError) {
      return { state: "not_sent" };
    }
    let plan: FinishPlan;
    try {
      plan = finishPlan(result);
    } catch {
      return { state: "not_sent" };
    }
    if (plan.action === "expire_lease") return { state: "lease_expiry" };
    const r = await this.#http.request(
      "/rest/v1/rpc/finish_animal_photo_cleanup_attempt",
      "POST",
      {
        p_animal_id: job.animalId,
        p_lease_token: job.leaseToken,
        p_generation: job.generation.toString(),
        p_outcome: plan.outcome,
        p_error_code: plan.errorCode,
      },
      this.#deadline(),
    );
    // Never retry automatically: the ACK may have committed before transport failed.
    if (!r.ok || typeof r.value !== "boolean") return { state: "uncertain" };
    return { state: r.value ? "accepted" : "rejected" };
  }
}
