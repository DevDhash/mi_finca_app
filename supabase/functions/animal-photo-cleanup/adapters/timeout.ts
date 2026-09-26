import type { CleanupBudget } from "../budget.ts";
import { timestampMicros } from "../terminal.ts";
import type { AdapterResult } from "../types.ts";

/** Includes body consumption. Abort is sent even if an injected transport ignores it. */
export async function withDeadline<T>(
  operation: (signal: AbortSignal) => Promise<T>,
  deadlineMs: number,
  now: () => number = Date.now,
): Promise<AdapterResult<T>> {
  const remaining = deadlineMs - now();
  if (!Number.isFinite(remaining) || remaining <= 0 || remaining > 2147483647) {
    return { ok: false, error: { kind: "timeout" } };
  }
  const controller = new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const expired = new Promise<AdapterResult<T>>((resolve) => {
    timer = setTimeout(() => {
      controller.abort();
      resolve({ ok: false, error: { kind: "timeout" } });
    }, Math.ceil(remaining));
  });
  const work = Promise.resolve().then(() => operation(controller.signal)).then(
    (value): AdapterResult<T> =>
      controller.signal.aborted || now() >= deadlineMs
        ? { ok: false, error: { kind: "timeout" } }
        : { ok: true, value },
    (): AdapterResult<T> => ({
      ok: false,
      error: { kind: controller.signal.aborted ? "timeout" : "network" },
    }),
  );
  try {
    return await Promise.race([work, expired]);
  } finally {
    clearTimeout(timer);
  }
}

/** Conservative wall-clock deadline: floor lease microseconds, reserve skew + ACK time.
 * Caller must provide a clock that does not move backwards during the invocation.
 */
export function leaseBudget(
  leaseExpiresAt: string,
  invocationDeadlineMs: number,
  now: () => number,
  requestMs = 5000,
  finishReserveMs = 5000,
  skewMs = 2000,
) {
  const lease = timestampMicros(leaseExpiresAt);
  if (
    lease === null || !Number.isSafeInteger(invocationDeadlineMs) ||
    ![requestMs, finishReserveMs, skewMs].every(Number.isSafeInteger) ||
    requestMs <= 0 || finishReserveMs <= 0 || skewMs < 0
  ) {
    throw new Error("INVALID_DEADLINE_CONFIG");
  }
  const deadline = Math.min(Number(lease / 1000n), invocationDeadlineMs) -
    skewMs;
  const remaining = () => deadline - now();
  const budget: CleanupBudget = Object.freeze({
    canStartList: () => remaining() > requestMs + finishReserveMs,
    canStartRemove: () => remaining() > requestMs + finishReserveMs,
    canFinish: () => remaining() > finishReserveMs,
  });
  return Object.freeze({
    budget,
    remainingMs: remaining,
    storageDeadline: () =>
      Math.min(now() + requestMs, deadline - finishReserveMs),
    finishDeadline: () => Math.min(now() + finishReserveMs, deadline),
  });
}
