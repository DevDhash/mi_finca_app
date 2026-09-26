import { deepStrictEqual, equal, ok } from "node:assert/strict";
import { test } from "node:test";
import { authenticate } from "../auth.ts";
import { readConfig } from "../config.ts";
import { json } from "./adapter_fakes.ts";
import { environment, harness, request, syntheticKey } from "./worker_fakes.ts";

for (
  const [label, headers, status] of [
    ["missing", {}, 401],
    ["invalid", { apikey: "wrong" }, 401],
    ["another secret", {
      apikey: "sb_secret_" + "different_synthetic_".repeat(2),
    }, 401],
    ["publishable", { apikey: "sb_publishable_synthetic" }, 401],
    ["user JWT only", { Authorization: "Bearer synthetic-user-token" }, 401],
    ["valid", { apikey: syntheticKey }, 200],
  ] as const
) {
  test(`handler auth ${label}`, async () => {
    const h = harness([json(0), json([])]);
    equal((await h.handler(request({ headers }))).status, status);
    equal(h.calls.length, status === 200 ? 2 : 0);
  });
}
for (const method of ["GET", "PUT", "DELETE", "OPTIONS"]) {
  test(`reject method ${method}`, async () => {
    const h = harness([]);
    const r = await h.handler(request({ method }));
    equal(r.status, 405);
    equal(r.headers.get("allow"), "POST");
    equal(h.calls.length, 0);
  });
}
for (
  const [name, value] of [
    ["SUPABASE_URL", undefined],
    ["SUPABASE_URL", "http://fixture.invalid"],
    ["SUPABASE_URL", "https://fixture.invalid/private"],
    ["SUPABASE_SECRET_KEYS", undefined],
    ["SUPABASE_SECRET_KEYS", "{"],
    ["SUPABASE_SECRET_KEYS", "[]"],
    ["SUPABASE_SECRET_KEYS", JSON.stringify({ default: syntheticKey })],
    ["ANIMAL_PHOTO_CLEANUP_MAX_JOBS", "5"],
    ["ANIMAL_PHOTO_CLEANUP_MAX_JOBS", "0"],
    ["ANIMAL_PHOTO_CLEANUP_INVOCATION_MS", "999999"],
    ["ANIMAL_PHOTO_CLEANUP_REQUEST_MS", "NaN"],
    ["ANIMAL_PHOTO_CLEANUP_MAX_BATCHES", "21"],
  ] as const
) {
  test(`invalid config ${name} ${String(value)}`, async () => {
    const h = harness([], { [name]: value });
    const r = await h.handler(request());
    equal(r.status, 503);
    equal(h.calls.length, 0);
    deepStrictEqual(await r.json(), { error: "configuration_unavailable" });
  });
}
for (
  const field of ["animal_id", "user_id", "bucket", "path", "object", "job_id"]
) {
  test(`caller cannot select ${field}`, async () => {
    for (const via of ["body", "query"]) {
      const h = harness([]);
      const r = await h.handler(
        via === "body"
          ? request({ body: JSON.stringify({ [field]: "synthetic-target" }) })
          : request({}, `?${field}=synthetic-target`),
      );
      equal(r.status, 400);
      equal(h.calls.length, 0);
    }
  });
}
test("empty body contract rejects even JSON empty object", async () => {
  const h = harness([]);
  equal((await h.handler(request({ body: "{}" }))).status, 400);
  equal(h.calls.length, 0);
});
test("named key only and legacy-only environment fails closed", async () => {
  equal(
    readConfig((name) =>
      name === "SUPABASE_SERVICE_ROLE_KEY"
        ? "synthetic-legacy"
        : name === "SUPABASE_URL"
        ? environment.SUPABASE_URL
        : undefined
    ),
    null,
  );
  equal(
    await authenticate(request(), "sb_secret_" + "other_synthetic_".repeat(2)),
    false,
  );
});
test("response and logs sanitize raw network exception", async () => {
  const marker = "SYNTHETIC_PRIVATE_DIAGNOSTIC";
  const h = harness([new Error(`${marker} ${syntheticKey}`)]);
  const r = await h.handler(request());
  equal(r.status, 503);
  const output = await r.text() + JSON.stringify(h.logs);
  ok(!output.includes(marker));
  ok(!output.includes(syntheticKey));
  ok(!output.includes("fixture.invalid"));
});
