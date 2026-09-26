import { equal, ok } from "node:assert/strict";
import { test } from "node:test";
import { leaseBudget, withDeadline } from "../adapters/timeout.ts";
import { HttpTransport } from "../adapters/http.ts";
import { StorageAdapter } from "../adapters/storage_adapter.ts";
import { job } from "./fakes.ts";
import { folder, options } from "./adapter_fakes.ts";
test("deadline normal response", async () => {
  const r = await withDeadline(async () => 42, Date.now() + 1000); ok(r.ok); equal(r.value, 42);
});
test("expired deadline starts no request", async () => {
  let called = false; const r = await withDeadline(async () => { called = true; }, 0); ok(!r.ok); equal(called, false);
});
for (const cooperative of [true, false]) test(`never responding request aborts; cooperative=${cooperative}`, async () => {
  let signal: AbortSignal | undefined;
  const r = await withDeadline((s) => { signal = s; return new Promise((_, reject) => {
    if (cooperative) s.addEventListener("abort", () => reject(new Error("aborted")));
  }); }, Date.now() + 10);
  ok(!r.ok); equal(r.error.kind, "timeout"); ok(signal?.aborted);
});
for (const stage of ["list", "remove"]) test(`abort during ${stage}`, async () => {
  let signal: AbortSignal | undefined;
  const http = new HttpTransport("https://fixture.invalid", {}, async (_, init) => { signal = init.signal!; return new Promise(() => {}); });
  const storage = new StorageAdapter(http, job, () => Date.now() + 10);
  const r = stage === "list" ? await storage.list(folder, options) : await storage.remove([`${folder}/aaaaaaaa-0000-4000-8000-000000000001.jpg`]);
  ok(!r.ok); equal(r.error.kind, "timeout"); ok(signal?.aborted);
});
const base = Date.parse("2026-01-01T00:00:00Z");
for (const [label, leaseMs, invocationMs, allowed] of [
  ["expired", -1, 60000, false], ["near expiry", 3000, 60000, false],
  ["invocation first", 60000, 3000, false], ["lease first", 3000, 60000, false],
  ["sufficient", 60000, 90000, true],
] as const) test(`budget ${label}`, () => {
  const b = leaseBudget(new Date(base + leaseMs).toISOString(), base + invocationMs, () => base);
  equal(b.budget.canStartList(), allowed); equal(b.budget.canStartRemove(), allowed);
  equal(b.remainingMs(), Math.min(leaseMs, invocationMs) - 2000);
});
test("budget gates change as clock advances; preserves finish reserve", () => {
  let now = base; const b = leaseBudget(new Date(base + 60000).toISOString(), base + 90000, () => now);
  equal(b.storageDeadline(), base + 5000); now += 50000;
  equal(b.budget.canStartList(), false); equal(b.budget.canFinish(), true); equal(b.finishDeadline(), now + 5000);
});

test("timeout covers response body, not just headers", async () => {
  let signal: AbortSignal | undefined;
  const http = new HttpTransport("https://fixture.invalid", {}, async (_, init) => {
    signal = init.signal!;
    return { ok: true, status: 200, text: async () => new Promise<string>(() => {}) } as Response;
  });
  const r = await http.request("/rest/v1/rpc/synthetic", "POST", {}, Date.now() + 10);
  ok(!r.ok); equal(r.error.kind, "timeout"); ok(signal?.aborted);
});
