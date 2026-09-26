import { equal, ok } from "node:assert/strict";
import { test } from "node:test";
import { createHandler } from "../handler.ts";
import type { Fetch } from "../adapters/http.ts";
import { json } from "./adapter_fakes.ts";
import { uuid } from "./fakes.ts";
import {
  baseTime,
  claimFor,
  environment,
  evidenceFor,
  request,
} from "./worker_fakes.ts";

function gate() {
  let release!: () => void;
  const promise = new Promise<void>((resolve) => {
    release = resolve;
  });
  return { promise, release };
}
const env = (name: string) =>
  name === "ANIMAL_PHOTO_CLEANUP_MAX_JOBS" ? "1" : environment[name];
test("two simultaneous workers claim distinct jobs in shared simulated ledger", async () => {
  const pending = [claimFor(0), claimFor(1)];
  const claimed: string[] = [];
  const finished: string[] = [];
  const bothClaimed = gate();
  const fetch: Fetch = async (url, init) => {
    const u = new URL(url);
    const body = init.body ? JSON.parse(init.body as string) : {};
    if (u.pathname.includes("discover_")) return json(0);
    if (u.pathname.includes("claim_")) {
      const job = pending.shift();
      if (!job) return json([]);
      claimed.push(job.animal_id);
      if (claimed.length === 2) bothClaimed.release();
      await bothClaimed.promise;
      return json([job]);
    }
    if (u.pathname.endsWith("sync_deletions")) {
      const i =
        u.searchParams.get("entity_id") === `eq.${claimFor(0).animal_id}`
          ? 0
          : 1;
      return json([evidenceFor(i)]);
    }
    if (u.pathname.includes("/object/list/")) return json([]);
    if (u.pathname.includes("finish_")) {
      const job = [claimFor(0), claimFor(1)].find((j) =>
        j.animal_id === body.p_animal_id
      )!;
      const valid = job.lease_token === body.p_lease_token &&
        job.generation === body.p_generation;
      if (valid) finished.push(job.animal_id);
      return json(valid);
    }
    throw new Error("UNEXPECTED_FAKE_OPERATION");
  };
  const first = createHandler(env, { fetch, now: () => baseTime });
  const second = createHandler(env, { fetch, now: () => baseTime });
  const responses = await Promise.all([first(request()), second(request())]);
  for (const response of responses) {
    equal((await response.json()).observedEmpty, 1);
  }
  equal(new Set(claimed).size, 2);
  equal(new Set(finished).size, 2);
});
test("old lease cannot ACK a newer generation: current worker accepted, stale rejected", async () => {
  const waiting = gate(), resumeOld = gate();
  let current = claimFor(0);
  let claims = 0, lists = 0;
  const acceptedGenerations: string[] = [];
  const fetch: Fetch = async (url, init) => {
    const path = new URL(url).pathname;
    const body = init.body ? JSON.parse(init.body as string) : {};
    if (path.includes("discover_")) return json(0);
    if (path.includes("claim_")) {
      claims++;
      if (claims === 2) {
        current = { ...current, generation: "2", lease_token: uuid(99) }; // Server expiry/reclaim simulated.
      }
      return json([{ ...current }]);
    }
    if (path.endsWith("sync_deletions")) return json([evidenceFor(0)]);
    if (path.includes("/object/list/")) {
      if (++lists === 1) {
        waiting.release();
        await resumeOld.promise;
      }
      return json([]);
    }
    if (path.includes("finish_")) {
      const valid = body.p_generation === current.generation &&
        body.p_lease_token === current.lease_token;
      if (valid) acceptedGenerations.push(body.p_generation);
      return json(valid);
    }
    throw new Error("UNEXPECTED_FAKE_OPERATION");
  };
  const first = createHandler(env, { fetch, now: () => baseTime });
  const second = createHandler(env, { fetch, now: () => baseTime });
  const oldResponse = first(request());
  await waiting.promise;
  const currentSummary = await (await second(request())).json();
  equal(currentSummary.observedEmpty, 1);
  resumeOld.release();
  const oldSummary = await (await oldResponse).json();
  equal(oldSummary.ackRejected, 1);
  equal(oldSummary.observedEmpty, 0);
  equal(acceptedGenerations.join(","), "2");
  ok(claims === 2);
});
