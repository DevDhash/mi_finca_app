import { deriveNamespace, pagePaths } from "../namespace.ts";
import { validJobMetadata } from "../terminal.ts";
import { PHOTO_BUCKET } from "../types.ts";
import type { AdapterResult, CleanupJob, ListOptions, PhotoStorage, StorageEntry } from "../types.ts";
import { HttpTransport, malformed, record } from "./http.ts";

/** Server-only, bound to validated claim identity; no HTTP caller-supplied bucket/path. */
export class StorageAdapter implements PhotoStorage {
  readonly bucket = PHOTO_BUCKET;
  readonly #job: CleanupJob;
  readonly #folder: string;
  readonly #http: HttpTransport;
  readonly #deadline: () => number;
  constructor(http: HttpTransport, claimedJob: CleanupJob, deadline: () => number) {
    const namespace = deriveNamespace(claimedJob);
    if (!namespace || !validJobMetadata(claimedJob)) throw new Error("INVALID_CLAIM");
    this.#job = Object.freeze({ ...claimedJob }); this.#folder = namespace.folder;
    this.#http = http; this.#deadline = deadline;
  }
  get fatalWorkerError(): boolean { return this.#http.fatalWorkerError; }
  async list(folder: string, options: ListOptions): Promise<AdapterResult<readonly StorageEntry[]>> {
    if (folder !== this.#folder || options?.limit !== 100 || options?.offset !== 0 ||
      options?.sortBy?.column !== "name" || options?.sortBy?.order !== "asc" || "search" in options) return malformed();
    const r = await this.#http.request(`/storage/v1/object/list/${PHOTO_BUCKET}`, "POST", {
      prefix: folder, limit: 100, offset: 0, sortBy: { column: "name", order: "asc" },
    }, this.#deadline());
    if (!r.ok) return r;
    if (!Array.isArray(r.value)) return malformed();
    return { ok: true, value: r.value.map((entry): StorageEntry => {
      if (!record(entry) || typeof entry.name !== "string") return { kind: "unexpected", name: "" };
      const kind = typeof entry.id === "string" && entry.id.length > 0 && record(entry.metadata)
        ? "file" : entry.id === null && entry.metadata === null ? "folder" : "unexpected";
      return { kind, name: entry.name };
    }) };
  }
  async remove(paths: readonly string[]): Promise<AdapterResult<unknown>> {
    if (!Array.isArray(paths) || paths.length < 1 || paths.length > 100 ||
      paths.some((p) => typeof p !== "string" || !p.startsWith(this.#folder + "/"))) return malformed();
    const validated = pagePaths(this.#job, paths.map((p) => ({ kind: "file", name: p.slice(this.#folder.length + 1) })));
    if (!validated || validated.some((p, i) => p !== paths[i])) return malformed();
    const r = await this.#http.request(`/storage/v1/object/${PHOTO_BUCKET}`, "DELETE", { prefixes: validated }, this.#deadline());
    if (!r.ok) return r;
    return Array.isArray(r.value) ? { ok: true, value: undefined } : malformed();
  }
}
