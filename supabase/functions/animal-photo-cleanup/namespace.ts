import type { CleanupJob, StorageEntry } from "./types.ts";

const UUID = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
// (?![\s\S]) is a strict end: unlike $, it cannot allow a final newline.
const UUID_PATTERN = new RegExp(`^${UUID}(?![\\s\\S])`);
const FILE_UUID = UUID.replaceAll("[0-9a-f]", "[0-9a-fA-F]");
// Match E1 exactly: filename hex is case-insensitive; extension is ASCII alnum+.
const FILE_PATTERN = new RegExp(`^${FILE_UUID}\\.[a-zA-Z0-9]+(?![\\s\\S])`);

export function isCanonicalUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_PATTERN.test(value);
}

export interface Namespace {
  readonly folder: string;
  readonly prefix: string;
}

export function deriveNamespace(
  job: Pick<CleanupJob, "userId" | "animalId">,
): Namespace | null {
  if (!isCanonicalUuid(job.userId) || !isCanonicalUuid(job.animalId)) return null;
  const folder = `${job.userId}/${job.animalId}`;
  return Object.freeze({ folder, prefix: `${folder}/` });
}

/** A single bad entry rejects the whole page; no path normalization. */
export function pagePaths(
  job: Pick<CleanupJob, "userId" | "animalId">,
  entries: readonly StorageEntry[],
): readonly string[] | null {
  const namespace = deriveNamespace(job);
  if (!namespace || !Array.isArray(entries) || entries.length > 100) return null;
  const paths = new Set<string>();
  for (const entry of entries) {
    if (
      !entry || entry.kind !== "file" || typeof entry.name !== "string" ||
      !FILE_PATTERN.test(entry.name)
    ) return null;
    const path = namespace.prefix + entry.name;
    if (paths.has(path)) return null;
    paths.add(path);
  }
  return Object.freeze([...paths]);
}
