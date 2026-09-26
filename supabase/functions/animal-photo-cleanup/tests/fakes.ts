import type { CleanupBudget } from "../budget.ts";
import { PHOTO_BUCKET } from "../types.ts";
import type {
  AdapterResult,
  CleanupJob,
  ListOptions,
  PhotoStorage,
  StorageEntry,
  TerminalRecord,
} from "../types.ts";

export const uuid = (n: number): string =>
  `aaaaaaaa-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
export const file = (n: number, extension = "jpg"): StorageEntry => ({
  kind: "file",
  name: `${uuid(n)}.${extension}`,
});
export const job: CleanupJob = Object.freeze({
  userId: uuid(1),
  animalId: uuid(2),
  tombstoneSequence: 9007199254740993n,
  operationId: uuid(3),
  deletedAt: "2026-01-01T00:00:00.123456+00:00",
  leaseToken: uuid(4),
  leaseExpiresAt: "2026-01-01T00:02:00.123456+00:00",
  generation: 1n,
});
export const ledger: TerminalRecord = Object.freeze({
  collection: "animals",
  entityId: job.animalId,
  userId: job.userId,
  sequence: job.tombstoneSequence,
  operationId: job.operationId,
  deletedAt: job.deletedAt,
});

export class FakeBudget implements CleanupBudget {
  lists = Infinity;
  removes = Infinity;
  finish = true;
  canStartList(): boolean {
    return this.lists-- > 0;
  }
  canStartRemove(): boolean {
    return this.removes-- > 0;
  }
  canFinish(): boolean {
    return this.finish;
  }
}

export class FakeStorage implements PhotoStorage {
  readonly bucket = PHOTO_BUCKET;
  entries: StorageEntry[];
  lists: { folder: string; options: ListOptions; size: number }[] = [];
  removals: (readonly string[])[] = [];
  beforeList?: (store: FakeStorage) => void;
  onList?: () => AdapterResult<readonly StorageEntry[]>;
  onRemove?: (paths: readonly string[]) => AdapterResult<unknown>;
  deleteLimit = Infinity;
  constructor(count = 0) {
    this.entries = Array.from({ length: count }, (_, n) => file(n + 100));
  }
  async list(
    folder: string,
    options: ListOptions,
  ): Promise<AdapterResult<readonly StorageEntry[]>> {
    this.beforeList?.(this);
    const value = [...this.entries].sort((a, b) => a.name.localeCompare(b.name))
      .slice(options.offset, options.offset + options.limit);
    this.lists.push({ folder, options, size: value.length });
    return this.onList?.() ?? { ok: true, value };
  }
  async remove(paths: readonly string[]): Promise<AdapterResult<unknown>> {
    this.removals.push([...paths]);
    if (this.onRemove) return this.onRemove(paths);
    const names = new Set(paths.slice(0, this.deleteLimit).map((p) => p.split("/").at(-1)));
    this.entries = this.entries.filter((e) => !names.has(e.name));
    // Deliberately return no deleted-object inventory.
    return { ok: true, value: undefined };
  }
}
