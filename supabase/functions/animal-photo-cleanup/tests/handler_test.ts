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

function streamRequest(
  body: ReadableStream<Uint8Array>,
  extraHeaders: Record<string, string> = {},
) {
  const init: RequestInit & { duplex: "half" } = {
    body,
    duplex: "half",
    headers: { apikey: syntheticKey, ...extraHeaders },
  };
  return request(init);
}

for (const length of [undefined, "0"]) {
  test(`existing zero-byte stream accepted, Content-Length ${length}`, async () => {
    const h = harness([json(0), json([])]);
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new Uint8Array(0));
        controller.close();
      },
    });
    const r = await h.handler(
      streamRequest(body, length ? { "content-length": length } : {}),
    );
    equal(r.status, 200);
    equal(h.calls.length, 2);
    equal(body.locked, false);
  });
}
for (const body of [null, ""]) {
  test(`empty body accepted: ${JSON.stringify(body)}`, async () => {
    const h = harness([json(0), json([])]);
    equal((await h.handler(request({ body }))).status, 200);
    equal(h.calls.length, 2);
  });
}
for (
  const payload of ["x", "{}", "[]", '""', " \n\t", '{"a":1}', "field=value"]
) {
  test(`actual payload rejected: ${JSON.stringify(payload)}`, async () => {
    const h = harness([]);
    const r = await h.handler(request({ body: payload }));
    equal(r.status, 400);
    deepStrictEqual(await r.json(), { error: "unexpected_input" });
    equal(h.calls.length, 0);
  });
}
const transportHeaders: Record<string, string>[] = [
  {},
  { "content-length": "0" },
  { "transfer-encoding": "chunked" },
];
for (const headers of transportHeaders) {
  test(`stream byte rejected regardless of headers: ${JSON.stringify(headers)}`, async () => {
    let cancelled = false;
    const body = new ReadableStream<Uint8Array>({
      pull(controller) {
        controller.enqueue(new Uint8Array([1]));
      },
      cancel() {
        cancelled = true;
      },
    }, { highWaterMark: 0 });
    const h = harness([]);
    equal((await h.handler(streamRequest(body, headers))).status, 400);
    equal(h.calls.length, 0);
    equal(cancelled, true);
    equal(body.locked, false);
  });
}
test("stream read failure fails closed", async () => {
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      controller.error(new Error("synthetic body failure"));
    },
  }, { highWaterMark: 0 });
  const h = harness([]);
  const r = await h.handler(streamRequest(body));
  equal(r.status, 400);
  deepStrictEqual(await r.json(), { error: "unexpected_input" });
  equal(h.calls.length, 0);
  equal(body.locked, false);
});
test("large payload rejected after first chunk without draining source", async () => {
  let pulls = 0, cancelled = false;
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      pulls++;
      controller.enqueue(new Uint8Array(1024 * 1024));
    },
    cancel() {
      cancelled = true;
    },
  }, { highWaterMark: 0 });
  const h = harness([]);
  equal((await h.handler(streamRequest(body))).status, 400);
  equal(pulls, 1);
  equal(cancelled, true);
  equal(body.locked, false);
  equal(h.calls.length, 0);
});
test("stalled body times out even if source cancellation never resolves", async () => {
  let cancelled = false;
  const body = new ReadableStream<Uint8Array>({
    cancel() {
      cancelled = true;
      return new Promise<void>(() => {});
    },
  }, { highWaterMark: 0 });
  const h = harness([], { ANIMAL_PHOTO_CLEANUP_REQUEST_MS: "100" });
  equal((await h.handler(streamRequest(body))).status, 400);
  equal(cancelled, true);
  equal(body.locked, false);
  equal(h.calls.length, 0);
});
test("endless empty chunks are bounded and cancelled", async () => {
  let pulls = 0, cancelled = false;
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      pulls++;
      controller.enqueue(new Uint8Array(0));
    },
    cancel() {
      cancelled = true;
    },
  }, { highWaterMark: 0 });
  const h = harness([]);
  equal((await h.handler(streamRequest(body))).status, 400);
  ok(pulls <= 16);
  equal(cancelled, true);
  equal(h.calls.length, 0);
});
test("unauthenticated request does not read the body", async () => {
  let pulls = 0;
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      pulls++;
      controller.enqueue(new Uint8Array([1]));
    },
  }, { highWaterMark: 0 });
  const h = harness([]);
  equal(
    (await h.handler(streamRequest(body, { apikey: "wrong" }))).status,
    401,
  );
  equal(pulls, 0);
  equal(h.calls.length, 0);
  await body.cancel();
});
