import { deepStrictEqual, equal, ok } from "node:assert/strict";
import { test } from "node:test";
import { JobsAdapter, finishPlan } from "../adapters/jobs_adapter.ts";
import { parseExactJson } from "../adapters/http.ts";
import { classifyError } from "../errors.ts";
import { job, uuid } from "./fakes.ts";
import { claimRow, terminalRow, deadline, json, transport, never } from "./adapter_fakes.ts";

for (const n of [0, 4, 5000]) test(`discover ${n}`, async () => {
  const { http, calls } = transport([json(n)]);
  deepStrictEqual(await new JobsAdapter(http, deadline).discover(5000), { ok: true, value: n });
  deepStrictEqual(JSON.parse(calls[0].init.body as string), { p_limit: 5000 });
});
for (const value of [null, [], {}, -1, 5001, 1.5, true]) test(`discover malformed ${JSON.stringify(value)}`, async () => {
  const { http } = transport([json(value)]);
  equal((await new JobsAdapter(http, deadline).discover(5000)).ok, false);
});
for (const limit of [0, -1, 5001, NaN, 1.5]) test(`discover rejects limit ${limit}`, async () => {
  const { http, calls } = transport([]);
  equal((await new JobsAdapter(http, deadline).discover(limit)).ok, false); equal(calls.length, 0);
});
for (const [reply, expected] of [[json({}, 403), "permission_denied"], [new Error("offline"), "storage_unavailable"], [never, "timeout"]] as const) {
  test(`discover ${expected}`, async () => {
    const { http } = transport([reply]);
    const r = await new JobsAdapter(http, () => Date.now() + 10).discover(100);
    ok(!r.ok); equal(classifyError(r.error), expected);
  });
}
test("claim none", async () => {
  const { http } = transport([json([])]);
  deepStrictEqual(await new JobsAdapter(http, deadline).claim(), { ok: true, value: null });
});
test("claim raw SQL bigint tokens preserve precision and timestamp", async () => {
  const raw = JSON.stringify([claimRow]).replace('"9007199254740993"', '9007199254740993');
  const { http, calls } = transport([new Response(raw)]);
  const r = await new JobsAdapter(http, deadline).claim();
  ok(r.ok && r.value); deepStrictEqual(r.value, job); ok(Object.isFrozen(r.value));
  equal(calls[0].init.body, "{}");
});
for (const [label, value] of [
  ["multiple", [claimRow, claimRow]], ["object", claimRow],
  ...Object.entries({ animal_id: "bad", user_id: "../", tombstone_operation_id: "bad", tombstone_sequence: "9223372036854775808", generation: 0, lease_token: null, lease_expires_at: "invalid", tombstone_deleted_at: "invalid", status: "pending" }).map(([key, value]) => [key, [{ ...claimRow, [key]: value }]]),
  ["fractional bigint", [{ ...claimRow, generation: 1.5 }]],
  ["exponent bigint", [{ ...claimRow, generation: "1e3" }]],
]) test(`claim rejects ${label}`, async () => {
  const { http } = transport([json(value)]); equal((await new JobsAdapter(http, deadline).claim()).ok, false);
});
for (const [label, rows, expected] of [
  ["exact", [terminalRow], "match"], ["missing", [], "mismatch"],
  ["owner", [{ ...terminalRow, user_id: uuid(88) }], "mismatch"],
  ["sequence", [{ ...terminalRow, sequence: "9007199254740994" }], "mismatch"],
  ["operation", [{ ...terminalRow, operation_id: uuid(89) }], "mismatch"],
  ["microsecond", [{ ...terminalRow, deleted_at: "2026-01-01T00:00:00.123457Z" }], "mismatch"],
  ["multiple", [terminalRow, terminalRow], "error"], ["malformed", [null], "error"],
] as const) test(`terminal ${label}`, async () => {
  const { http, calls } = transport([json([claimRow]), json(rows)]);
  const jobs = new JobsAdapter(http, deadline); const claim = await jobs.claim(); ok(claim.ok && claim.value);
  const r = await jobs.getTerminalEvidence(claim.value);
  equal(r.ok ? "match" : "terminalMismatch" in r ? "mismatch" : "error", expected);
  const url = new URL(calls[1].url);
  equal(url.pathname, "/rest/v1/sync_deletions"); equal(url.searchParams.get("collection"), "eq.animals");
  equal(url.searchParams.get("entity_id"), `eq.${job.animalId}`); equal(url.searchParams.get("user_id"), `eq.${job.userId}`);
});
for (const [label, response, state] of [
  ["accepted", json(true), "accepted"], ["rejected", json(false), "rejected"],
  ["malformed", json({}), "uncertain"], ["timeout", never, "uncertain"],
  ["network", new Error("lost ACK"), "uncertain"],
] as const) test(`finish ${label}`, async () => {
  const { http, calls } = transport([json([claimRow]), response]);
  const jobs = new JobsAdapter(http, () => Date.now() + 20); const claim = await jobs.claim(); ok(claim.ok && claim.value);
  deepStrictEqual(await jobs.finish(claim.value, { outcome: "observed_empty" }), { state });
  equal(calls.length, 2);
  deepStrictEqual(JSON.parse(calls[1].init.body as string), {
    p_animal_id: job.animalId, p_lease_token: job.leaseToken, p_generation: "1", p_outcome: "observed_empty", p_error_code: null,
  });
});
test("unclaimed identities cannot read ledger or finish", async () => {
  const { http, calls } = transport([]); const jobs = new JobsAdapter(http, deadline);
  equal((await jobs.getTerminalEvidence(job)).ok, false);
  equal((await jobs.finish(job, { outcome: "observed_empty" })).state, "not_sent"); equal(calls.length, 0);
});
test("budget exhaustion deliberately expires lease without finish", async () => {
  const { http, calls } = transport([json([claimRow])]); const jobs = new JobsAdapter(http, deadline);
  const claim = await jobs.claim(); ok(claim.ok && claim.value);
  equal((await jobs.finish(claim.value, { outcome: "retry", errorCode: "budget_exhausted" })).state, "lease_expiry"); equal(calls.length, 1);
});
for (const errorCode of ["storage_unavailable", "rate_limited", "timeout", "internal_error", "permission_denied", "no_progress"] as const) {
  test(`mapping retry ${errorCode}`, () => deepStrictEqual(finishPlan({ outcome: "retry", errorCode }), { action: "finish", outcome: "retry", errorCode }));
}
for (const errorCode of ["terminal_mismatch", "invalid_namespace", "legacy_conflict"] as const) {
  test(`mapping structural ${errorCode}`, () => deepStrictEqual(finishPlan({ outcome: "quarantined", errorCode }), { action: "finish", outcome: "quarantined", errorCode }));
}
test("exact JSON preserves strings and integer tokens", () => {
  deepStrictEqual(parseExactJson('{"n":9223372036854775807,"text":"123 \\" 456","v":1.2}'), { n: "9223372036854775807", text: '123 " 456', v: 1.2 });
});

test("finish generation never rounds through Number", async () => {
  const raw = JSON.stringify([{ ...claimRow, generation: "9223372036854775807" }]).replace('"9223372036854775807"', '9223372036854775807');
  const { http, calls } = transport([new Response(raw), json(true)]);
  const jobs = new JobsAdapter(http, deadline); const claimed = await jobs.claim(); ok(claimed.ok && claimed.value);
  equal((await jobs.finish(claimed.value, { outcome: "observed_empty" })).state, "accepted");
  equal(JSON.parse(calls[1].init.body as string).p_generation, "9223372036854775807");
});
for (const field of Object.keys(claimRow)) test(`claim missing ${field}`, async () => {
  const row: Record<string, unknown> = { ...claimRow }; delete row[field];
  const { http } = transport([json([row])]); equal((await new JobsAdapter(http, deadline).claim()).ok, false);
});

test("bigint string with trailing newline rejected", async () => {
  const { http } = transport([json([{ ...claimRow, generation: "1\n" }])]);
  equal((await new JobsAdapter(http, deadline).claim()).ok, false);
});
test("discovery count with trailing newline rejected", async () => {
  const { http } = transport([json("1\n")]);
  equal((await new JobsAdapter(http, deadline).discover(100)).ok, false);
});
