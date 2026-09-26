import type { CleanupBudget } from "./budget.ts";
import { classifyError } from "./errors.ts";
import { deriveNamespace, pagePaths } from "./namespace.ts";
import { compareTerminal, validJobMetadata } from "./terminal.ts";
import { PHOTO_BUCKET } from "./types.ts";
import type {
  CleanupJob,
  CleanupResult,
  ListOptions,
  PhotoStorage,
  TerminalRecord,
} from "./types.ts";

const LIST_OPTIONS: ListOptions = Object.freeze({
  limit: 100,
  offset: 0,
  sortBy: Object.freeze({ column: "name", order: "asc" }),
});
const TIMEOUT: CleanupResult = Object.freeze({
  outcome: "retry",
  errorCode: "timeout",
});
const INVALID: CleanupResult = Object.freeze({
  outcome: "quarantined",
  errorCode: "invalid_namespace",
});

/** Local orchestration only; no discovery, claim, finish or network adapter.
 * Ledger evidence must be fetched/trusted by the future server orchestrator.
 * Results are proposals, not durable E1 acknowledgements.
 */
export async function cleanup(
  inputJob: CleanupJob,
  ledger: TerminalRecord | null,
  storage: PhotoStorage,
  budget: CleanupBudget,
  maxBatches = 20,
): Promise<CleanupResult> {
  // Snapshot immutable identity before the first await.
  const job = Object.freeze({ ...inputJob });
  const namespace = deriveNamespace(job);
  if (!namespace || storage.bucket !== PHOTO_BUCKET) return INVALID;
  if (
    !validJobMetadata(job) || !Number.isSafeInteger(maxBatches) ||
    maxBatches < 1
  ) {
    return { outcome: "retry", errorCode: "internal_error" };
  }
  if (compareTerminal(job, ledger)) {
    return { outcome: "quarantined", errorCode: "terminal_mismatch" };
  }
  let batches = 0;
  let emptyReads = 0;
  let stalledCycles = 0;
  let previousPaths: readonly string[] | null = null;
  try {
    while (true) {
      if (!budget.canStartList()) return TIMEOUT;
      const page = await storage.list(namespace.folder, LIST_OPTIONS);
      if (!page.ok) {
        return { outcome: "retry", errorCode: classifyError(page.error) };
      }
      if (!Array.isArray(page.value)) {
        return { outcome: "retry", errorCode: "internal_error" };
      }
      const paths = pagePaths(job, page.value);
      if (paths === null) return INVALID;
      if (previousPaths !== null) {
        const current = new Set(paths);
        stalledCycles = previousPaths.every((path) => current.has(path))
          ? stalledCycles + 1
          : 0;
        previousPaths = null;
      }
      if (paths.length === 0) {
        emptyReads++;
        if (emptyReads === 2) {
          return budget.canFinish() ? { outcome: "observed_empty" } : TIMEOUT;
        }
        continue;
      }
      emptyReads = 0;
      if (!budget.canStartRemove()) return TIMEOUT;
      if (stalledCycles >= 2) {
        return { outcome: "retry", errorCode: "no_progress" };
      }
      if (batches >= maxBatches) {
        return { outcome: "retry", errorCode: "budget_exhausted" };
      }
      const removal = await storage.remove(paths);
      if (!removal.ok) {
        return { outcome: "retry", errorCode: classifyError(removal.error) };
      }
      // Do not infer progress from removal.value (may represent a partial delete).
      batches++;
      previousPaths = paths;
    }
  } catch {
    // A raw exception violates the adapter contract; never echo its message.
    return { outcome: "retry", errorCode: "internal_error" };
  }
}
