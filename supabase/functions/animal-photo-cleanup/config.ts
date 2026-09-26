export type Environment = (name: string) => string | undefined;
export interface WorkerConfig {
  readonly url: string;
  readonly secret: string;
  readonly maxJobs: number;
  readonly discoveryLimit: number;
  readonly invocationMs: number;
  readonly requestMs: number;
  readonly finishMs: number;
  readonly skewMs: number;
  readonly maxBatches: number;
}
export function validSecret(value: unknown): value is string {
  return typeof value === "string" && /^sb_secret_[A-Za-z0-9_-]{20,256}(?![\s\S])/.test(value);
}
/** Configuration errors deliberately carry no input values. No legacy-key fallback. */
export function readConfig(env: Environment): WorkerConfig | null {
  try {
    const url = new URL(env("SUPABASE_URL") ?? "");
    if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash || url.pathname !== "/") return null;
    const raw = env("SUPABASE_SECRET_KEYS");
    if (!raw || raw.length > 32768) return null;
    const keys: unknown = JSON.parse(raw);
    const name = env("ANIMAL_PHOTO_CLEANUP_KEY_NAME") ?? "animal-photo-cleanup";
    if (!keys || typeof keys !== "object" || Array.isArray(keys) || !Object.hasOwn(keys, name)) return null;
    const secret = (keys as Record<string, unknown>)[name];
    if (!validSecret(secret)) return null;
    const number = (name: string, fallback: number, min: number, max: number) => {
      const text = env(name);
      if (text !== undefined && !/^[1-9]\d{0,5}(?![\s\S])/.test(text)) throw new Error("INVALID_CONFIG");
      const value = text === undefined ? fallback : Number(text);
      if (value < min || value > max) throw new Error("INVALID_CONFIG");
      return value;
    };
    const config = {
      url: url.origin, secret,
      maxJobs: number("ANIMAL_PHOTO_CLEANUP_MAX_JOBS", 4, 1, 4),
      discoveryLimit: number("ANIMAL_PHOTO_CLEANUP_DISCOVERY_LIMIT", 1000, 1, 5000),
      invocationMs: number("ANIMAL_PHOTO_CLEANUP_INVOCATION_MS", 90000, 15000, 90000),
      requestMs: number("ANIMAL_PHOTO_CLEANUP_REQUEST_MS", 5000, 100, 10000),
      finishMs: number("ANIMAL_PHOTO_CLEANUP_FINISH_MS", 5000, 100, 10000),
      skewMs: number("ANIMAL_PHOTO_CLEANUP_SKEW_MS", 2000, 100, 10000),
      maxBatches: number("ANIMAL_PHOTO_CLEANUP_MAX_BATCHES", 20, 1, 20),
    };
    if (config.invocationMs <= config.requestMs * 2 + config.finishMs + config.skewMs) return null;
    return Object.freeze(config);
  } catch { return null; }
}
