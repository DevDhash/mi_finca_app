import { deepStrictEqual, equal, ok } from "node:assert/strict";
import { test } from "node:test";
import { JobsAdapter } from "../adapters/jobs_adapter.ts";
import { StorageAdapter } from "../adapters/storage_adapter.ts";
import { cleanup } from "../cleanup.ts";
import { FakeBudget, file, uuid } from "./fakes.ts";
import {
  claimRow,
  deadline,
  json,
  never,
  terminalRow,
  transport,
} from "./adapter_fakes.ts";

for (
  const scenario of [
    "empty",
    "retry",
    "structural",
    "stale",
    "uncertain",
  ] as const
) {
  test(`local integration claim → evidence → cleanup → finish: ${scenario}`, async () => {
    const listReplies = scenario === "retry"
      ? [json({}, 429)]
      : scenario === "structural"
      ? [json([{ name: "unexpected-folder", id: null, metadata: null }])]
      : [
        json([{ name: file(7).name, id: uuid(7), metadata: {} }]),
        json([]),
        json([]),
        json([]),
      ];
    const { http, calls } = transport([
      json([claimRow]),
      json([terminalRow]),
      ...listReplies,
      scenario === "uncertain" ? never : json(scenario !== "stale"),
    ]);
    const jobs = new JobsAdapter(
      http,
      scenario === "uncertain" ? () => Date.now() + 20 : deadline,
    );
    const claimed = await jobs.claim();
    ok(claimed.ok && claimed.value);
    const evidence = await jobs.getTerminalEvidence(claimed.value);
    ok(evidence.ok);
    const result = await cleanup(
      claimed.value,
      evidence.value,
      new StorageAdapter(http, claimed.value, deadline),
      new FakeBudget(),
    );
    equal(
      result.outcome,
      scenario === "retry"
        ? "retry"
        : scenario === "structural"
        ? "quarantined"
        : "observed_empty",
    );
    const finish = await jobs.finish(claimed.value, result);
    equal(
      finish.state,
      scenario === "stale"
        ? "rejected"
        : scenario === "uncertain"
        ? "uncertain"
        : "accepted",
    );
    const last = calls.at(-1)!;
    equal(
      new URL(last.url).pathname,
      "/rest/v1/rpc/finish_animal_photo_cleanup_attempt",
    );
    equal(JSON.parse(last.init.body as string).p_outcome, result.outcome);
    equal(calls.filter((c) => c.url.includes("/rpc/finish_")).length, 1);
  });
}
test("administrative fault stops work and does not finish permission_denied per job", async () => {
  const { http, calls } = transport([
    json([claimRow]),
    json([terminalRow]),
    json({}, 403),
  ]);
  const jobs = new JobsAdapter(http, deadline);
  const claimed = await jobs.claim();
  ok(claimed.ok && claimed.value);
  const evidence = await jobs.getTerminalEvidence(claimed.value);
  ok(evidence.ok);
  const result = await cleanup(
    claimed.value,
    evidence.value,
    new StorageAdapter(http, claimed.value, deadline),
    new FakeBudget(),
  );
  ok(jobs.fatalWorkerError);
  deepStrictEqual(result, { outcome: "retry", errorCode: "permission_denied" });
  equal((await jobs.finish(claimed.value, result)).state, "not_sent");
  equal((await jobs.claim()).ok, false);
  equal(calls.length, 3);
});
