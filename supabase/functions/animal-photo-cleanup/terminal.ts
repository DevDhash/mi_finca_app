import { isCanonicalUuid } from "./namespace.ts";
import type { CleanupJob, TerminalRecord } from "./types.ts";

const PG_BIGINT_MAX = 9223372036854775807n;
function positiveSqlInteger(value: unknown): value is bigint {
  return typeof value === "bigint" && value > 0n && value <= PG_BIGINT_MAX;
}

/** Parse supported ISO/SQL timestamps at exact microsecond precision.
 * Date is used ONLY for integral calendar seconds, never fractional seconds.
 * Reject unsupported precision rather than silently rounding it.
 */
export function timestampMicros(value: string): bigint | null {
  if (typeof value !== "string") return null;
  const match = /^(\d{4}-\d{2}-\d{2})[T ](\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})(?![\s\S])/.exec(value);
  if (!match) return null;
  const [, date, hour, minute, second, fraction = "", zone] = match;
  if (date.startsWith("0000") || +hour > 23 || +minute > 59 || +second > 59) {
    return null;
  }
  const integral = `${date}T${hour}:${minute}:${second}.000Z`;
  const millis = Date.parse(integral);
  if (!Number.isFinite(millis) || new Date(millis).toISOString() !== integral) {
    return null;
  }
  let offsetMinutes = 0;
  if (zone !== "Z") {
    const hours = Number(zone.slice(1, 3));
    const minutes = Number(zone.slice(4, 6));
    if (hours > 23 || minutes > 59) return null;
    offsetMinutes = (hours * 60 + minutes) * (zone[0] === "+" ? 1 : -1);
  }
  return BigInt(millis) * 1000n + BigInt(fraction.padEnd(6, "0")) -
    BigInt(offsetMinutes) * 60000000n;
}

export function validJobMetadata(job: CleanupJob): boolean {
  return positiveSqlInteger(job.tombstoneSequence) &&
    positiveSqlInteger(job.generation) &&
    isCanonicalUuid(job.operationId) && isCanonicalUuid(job.leaseToken) &&
    timestampMicros(job.deletedAt) !== null &&
    timestampMicros(job.leaseExpiresAt) !== null;
}

/** No animals row, photo reference, local state, or database query participates. */
export function compareTerminal(
  job: CleanupJob,
  ledger: TerminalRecord | null,
): "terminal_mismatch" | null {
  const deletedAt = timestampMicros(job.deletedAt);
  return ledger !== null && validJobMetadata(job) &&
      isCanonicalUuid(job.userId) && isCanonicalUuid(job.animalId) &&
      ledger.collection === "animals" && ledger.entityId === job.animalId &&
      ledger.userId === job.userId && ledger.sequence === job.tombstoneSequence &&
      ledger.operationId === job.operationId && deletedAt !== null &&
      timestampMicros(ledger.deletedAt) === deletedAt
    ? null
    : "terminal_mismatch";
}
