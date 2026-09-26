import { equal, ok } from "node:assert/strict";
import { test } from "node:test";
import { json, never } from "./adapter_fakes.ts";
import { file, uuid } from "./fakes.ts";
import {
  claimFor,
  evidenceFor,
  harness,
  request,
  successfulJob,
  syntheticKey,
} from "./worker_fakes.ts";

const countCalls = (h: ReturnType<typeof harness>, contains: string) =>
  h.calls.filter((c) => c.path.includes(contains)).length;
for (const objects of [0, 1, 100]) {
  test(`HTTP → discover → claim → terminal → cleanup ${objects} → ACK`, async () => {
    const entries = Array.from(
      { length: objects },
      (_, i) => ({ id: uuid(i), name: file(i).name, metadata: {} }),
    );
    const h = harness([
      json(1),
      json([claimFor(0)]),
      json([evidenceFor(0)]),
      ...(objects ? [json(entries), json([])] : []),
      json([]),
      json([]),
      json(true),
      json([]),
    ]);
    const r = await h.handler(request());
    equal(r.status, 200);
    const s = await r.json();
    equal(s.observedEmpty, 1);
    equal(s.claimed, 1);
    equal(s.processed, 1);
    equal(countCalls(h, "discover"), 1);
    equal(countCalls(h, "/object/list/"), objects ? 3 : 2);
    for (const c of h.calls.filter((c) => c.path.includes("/object/list/"))) {
      equal(c.body!.offset, 0);
      equal(c.body!.limit, 100);
      ok(!("search" in c.body!));
    }
    for (const c of h.calls) {
      const headers = new Headers(c.init.headers);
      equal(headers.get("apikey"), syntheticKey);
      equal(headers.get("Authorization"), null);
    }
  });
}
test("claim none terminates normally", async () => {
  const h = harness([json(0), json([])]);
  const s = await (await h.handler(request())).json();
  equal(s.claimed, 0);
  equal(h.calls.length, 2);
});
test("max four jobs sequentially, discovery once", async () => {
  const h = harness([
    json(4),
    ...Array.from({ length: 4 }, (_, i) => successfulJob(i)).flat(),
  ]);
  const s = await (await h.handler(request())).json();
  equal(s.observedEmpty, 4);
  equal(s.claimed, 4);
  equal(countCalls(h, "claim_animal"), 4);
  equal(countCalls(h, "discover"), 1);
  const stages = h.calls.map((c) => c.path.split("/").at(-1));
  for (let i = 0; i < 4; i++) {
    equal(stages[1 + i * 5], "claim_animal_photo_cleanup_job");
  }
});
test("discovery failure prevents claim", async () => {
  const h = harness([json({}, 503)]);
  const s = await (await h.handler(request())).json();
  equal(s.stopped, "error");
  equal(countCalls(h, "claim_animal"), 0);
});
for (
  const phase of ["discovery", "claim", "terminal", "list", "remove", "finish"]
) {
  for (const status of [401, 403]) {
    test(`fatal ${status} at ${phase} stops entire invocation`, async () => {
      const sequence = [
        json(1),
        json([claimFor(0)]),
        json([evidenceFor(0)]),
        json([{ name: file(1).name, id: uuid(1), metadata: {} }]),
        json([]),
        json([]),
        json([]),
        json(true),
      ];
      const idx = {
        discovery: 0,
        claim: 1,
        terminal: 2,
        list: 3,
        remove: 4,
        finish: 7,
      }[phase]!;
      const h = harness([
        ...sequence.slice(0, idx),
        json({ message: "synthetic-sensitive" }, status),
      ]);
      const response = await h.handler(request());
      equal(response.status, 503);
      const s = await response.json();
      equal(s.fatal, true);
      equal(s.quarantined, 0);
      equal(s.retry, 0);
      equal(h.calls.length, idx + 1);
      equal(countCalls(h, "claim_animal"), phase === "discovery" ? 0 : 1);
    });
  }
}
for (const accepted of [true, false, "sql-error"]) {
  test(`terminal mismatch: no Storage; finish ${accepted}`, async () => {
    const h = harness([
      json(1),
      json([claimFor(0)]),
      json([]),
      accepted === "sql-error" ? json({ code: "23514" }, 400) : json(accepted),
      ...(accepted === true ? [json([])] : []),
    ]);
    const s = await (await h.handler(request())).json();
    equal(countCalls(h, "/storage/"), 0);
    equal(s.interventionRequired, accepted !== true);
    equal(countCalls(h, "finish_"), 1);
    equal(h.calls[3].body!.p_error_code, "terminal_mismatch");
  });
}
for (
  const [reply, outcome, counter] of [[json({}, 429), "retry", "retry"], [
    json([{ name: "folder", id: null, metadata: null }]),
    "quarantined",
    "quarantined",
  ]] as const
) {
  test(`cleanup ${outcome} mapped to E1`, async () => {
    const h = harness([
      json(1),
      json([claimFor(0)]),
      json([evidenceFor(0)]),
      reply,
      json(true),
      json([]),
    ]);
    const s = await (await h.handler(request())).json();
    equal(s[counter], 1);
    equal(h.calls[4].body!.p_outcome, outcome);
  });
}
test("budget_exhausted expires lease, NO finish", async () => {
  const entries = Array.from(
    { length: 100 },
    (_, i) => ({ id: uuid(i), name: file(i).name, metadata: {} }),
  );
  const h = harness([
    json(1),
    json([claimFor(0)]),
    json([evidenceFor(0)]),
    json(entries),
    json([]),
    json([{ id: uuid(101), name: file(101).name, metadata: {} }]),
  ], { ANIMAL_PHOTO_CLEANUP_MAX_BATCHES: "1" });
  const s = await (await h.handler(request())).json();
  equal(s.leaseExpiry, 1);
  equal(s.stopped, "lease_expiry");
  equal(countCalls(h, "finish_"), 0);
});
for (const ack of ["stale", "timeout"]) {
  test(`finish ${ack}: no retry or further claim`, async () => {
    const h = harness([
      json(1),
      json([claimFor(0)]),
      json([evidenceFor(0)]),
      json([]),
      json([]),
      ack === "stale" ? json(false) : never,
    ], { ANIMAL_PHOTO_CLEANUP_FINISH_MS: "100" });
    const s = await (await h.handler(request())).json();
    equal(s.observedEmpty, 0);
    equal(s[ack === "stale" ? "ackRejected" : "ackUncertain"], 1);
    equal(countCalls(h, "finish_"), 1);
    equal(countCalls(h, "claim_animal"), 1);
  });
}
test("deadline after discovery prevents claim", async () => {
  const h = harness([() => {
    h.advance(89000);
    return Promise.resolve(json(0));
  }]);
  const s = await (await h.handler(request())).json();
  equal(countCalls(h, "claim_animal"), 0);
  ok(["error", "deadline"].includes(s.stopped));
});
test("expired lease prevents terminal and Storage I/O", async () => {
  const h = harness([
    json(1),
    json([{ ...claimFor(0), lease_expires_at: "2025-12-31T23:59:00Z" }]),
  ]);
  const s = await (await h.handler(request())).json();
  equal(s.leaseExpiry, 1);
  equal(h.calls.length, 2);
});
test("safe logs and summary exclude identity paths and credentials", async () => {
  const h = harness([json(1), ...successfulJob(), json([])]);
  const r = await h.handler(request());
  const text = await r.text() + JSON.stringify(h.logs);
  for (
    const forbidden of [
      syntheticKey,
      claimFor(0).animal_id,
      claimFor(0).user_id,
      "https://",
      "Authorization",
      "lease_token",
    ]
  ) ok(!text.includes(forbidden));
  ok(text.length < 4000);
  equal(r.headers.get("cache-control"), "no-store");
});

test("late upload between empty reads is removed before confirmed ACK", async () => {
  const late = { id: uuid(8), name: file(8).name, metadata: {} };
  const h = harness([
    json(1),
    json([claimFor(0)]),
    json([evidenceFor(0)]),
    json([]),
    json([late]),
    json([]),
    json([]),
    json([]),
    json(true),
    json([]),
  ]);
  const s = await (await h.handler(request())).json();
  equal(s.observedEmpty, 1);
  equal(h.calls.filter((c) => c.init.method === "DELETE").length, 1);
  equal(countCalls(h, "/object/list/"), 4);
});
test("duplicate claim does not repeat cleanup of the same animal in an invocation", async () => {
  const h = harness([
    json(1),
    ...successfulJob(),
    json([{ ...claimFor(0), generation: "2" }]),
  ]);
  const s = await (await h.handler(request())).json();
  equal(s.stopped, "duplicate");
  equal(s.leaseExpiry, 1);
  equal(s.observedEmpty, 1);
  equal(countCalls(h, "finish_"), 1);
});
