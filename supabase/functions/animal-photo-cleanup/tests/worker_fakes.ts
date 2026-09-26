import { createHandler } from "../handler.ts";
import { readConfig } from "../config.ts";
import type { Fetch } from "../adapters/http.ts";
import { claimRow, terminalRow, json } from "./adapter_fakes.ts";
import { uuid } from "./fakes.ts";
export const syntheticKey = "sb_secret_" + "synthetic_fixture_only_".repeat(2);
export const baseTime = Date.parse("2026-01-01T00:00:00Z");
export const environment: Record<string, string> = {
  SUPABASE_URL: "https://fixture.invalid",
  SUPABASE_SECRET_KEYS: JSON.stringify({ "animal-photo-cleanup": syntheticKey }),
};
export const config = readConfig((name) => environment[name])!;
export const claimFor = (i: number) => ({ ...claimRow, animal_id: uuid(100 + i), tombstone_sequence: String(i + 1) });
export const evidenceFor = (i: number) => ({ ...terminalRow, entity_id: uuid(100 + i), sequence: String(i + 1) });
export function harness(replies: (Response | Fetch | Error)[], overrides: Record<string, string | undefined> = {}) {
  const env = { ...environment, ...overrides };
  const calls: { path: string; body: Record<string, unknown> | undefined; init: RequestInit }[] = [];
  const logs: unknown[] = [];
  let clock = baseTime;
  const fetch: Fetch = async (url, init) => {
    calls.push({ path: new URL(url).pathname, body: init.body ? JSON.parse(init.body as string) : undefined, init });
    const next = replies.shift();
    if (next instanceof Error) throw next;
    if (typeof next === "function") return next(url, init);
    if (!next) throw new Error("UNEXPECTED_SYNTHETIC_REQUEST");
    return next;
  };
  const deps = { fetch, now: () => clock, log: (event: unknown) => { logs.push(event); } };
  const handler = createHandler((name) => env[name], deps);
  return { handler, deps, calls, logs, advance: (ms: number) => { clock += ms; } };
}
export const request = (init: RequestInit = {}, query = "") => new Request(`https://endpoint.invalid/animal-photo-cleanup${query}`, {
  method: "POST", headers: { apikey: syntheticKey }, ...init,
});
export const successfulJob = (i = 0) => [json([claimFor(i)]), json([evidenceFor(i)]), json([]), json([]), json(true)];
