export const PHOTO_BUCKET = "animal-photos" as const;

/** Integers are bigint internally: never deserialize SQL bigint through Number. */
export interface CleanupJob {
  readonly animalId: string;
  readonly userId: string;
  readonly tombstoneSequence: bigint;
  readonly operationId: string;
  readonly deletedAt: string;
  readonly leaseToken: string;
  readonly leaseExpiresAt: string;
  readonly generation: bigint;
}

export interface TerminalRecord {
  readonly collection: string;
  readonly entityId: string;
  readonly userId: string;
  readonly sequence: bigint;
  readonly operationId: string;
  readonly deletedAt: string;
}

export type ErrorCode =
  | "storage_unavailable"
  | "rate_limited"
  | "timeout"
  | "internal_error"
  | "permission_denied"
  | "no_progress"
  | "terminal_mismatch"
  | "invalid_namespace"
  | "legacy_conflict"
  | "budget_exhausted";

/** Internal outcome only. In particular budget_exhausted is NOT an E1 code. */
export type CleanupResult =
  | { readonly outcome: "observed_empty" }
  | { readonly outcome: "retry"; readonly errorCode: ErrorCode }
  | {
    readonly outcome: "quarantined";
    readonly errorCode:
      | "terminal_mismatch"
      | "invalid_namespace"
      | "legacy_conflict";
  };

export interface NormalizedError {
  readonly kind: "network" | "timeout" | "http" | "unknown";
  readonly status?: number;
  readonly code?: string;
}

export type AdapterResult<T> =
  | { readonly ok: true; readonly value: T }
  | { readonly ok: false; readonly error: NormalizedError };

export interface StorageEntry {
  readonly kind: "file" | "folder" | "unexpected";
  readonly name: string;
}

export interface ListOptions {
  readonly limit: 100;
  readonly offset: 0;
  readonly sortBy: { readonly column: "name"; readonly order: "asc" };
}

/** Future adapter must be bound to PHOTO_BUCKET, never to caller-supplied input. */
export interface PhotoStorage {
  readonly bucket: typeof PHOTO_BUCKET;
  list(
    folder: string,
    options: ListOptions,
  ): Promise<AdapterResult<readonly StorageEntry[]>>;
  /** The response is intentionally opaque; only re-list establishes progress. */
  remove(paths: readonly string[]): Promise<AdapterResult<unknown>>;
}
