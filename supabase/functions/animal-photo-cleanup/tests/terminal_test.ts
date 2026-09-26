import { equal } from "node:assert/strict";
import { test } from "node:test";
import { compareTerminal, timestampMicros, validJobMetadata } from "../terminal.ts";
import type { TerminalRecord } from "../types.ts";
import { job, ledger, uuid } from "./fakes.ts";

test("matching terminal record needs no animal or photo reference", () => {
  equal(compareTerminal(job, ledger), null);
  equal(compareTerminal(job, null), "terminal_mismatch");
});
const mutations: Partial<TerminalRecord>[] = [
  { collection: "expenses" },
  { entityId: uuid(55) },
  { userId: uuid(56) },
  { sequence: job.tombstoneSequence + 1n },
  { operationId: uuid(57) },
  { deletedAt: "2026-01-01T00:00:00.123457Z" },
  { deletedAt: "invalid" },
];
for (const change of mutations) {
  test(`terminal mismatch on ${Object.keys(change)[0]}`, () => {
    equal(compareTerminal(job, { ...ledger, ...change }), "terminal_mismatch");
  });
}
test("timestamps retain microseconds and compare equivalent offsets", () => {
  equal(compareTerminal(job, { ...ledger, deletedAt: "2025-12-31T19:00:00.123456-05:00" }), null);
  equal(timestampMicros("2026-01-01T00:00:00.123456Z")! -
    timestampMicros("2026-01-01T00:00:00.123455Z")!, 1n);
  equal(timestampMicros("2026-01-01 00:00:00.1+00:00"),
    timestampMicros("2026-01-01T00:00:00.100000Z"));
});
for (const invalid of [
  "2026-02-30T00:00:00Z", "2026-01-01T24:00:00Z", "2026-01-01T00:00:60Z",
  "2026-01-01T00:00:00.1234567Z", "2026-01-01T00:00:00", "infinity",
  "2026-01-01T00:00:00+24:00", "2026-01-01T00:00:00+00:60",
  "2026-01-01T00:00:00Z\n",
]) {
  test(`unsupported timestamp rejected: ${JSON.stringify(invalid)}`, () => {
    equal(timestampMicros(invalid), null);
  });
}
test("bigint is exact; Number and invalid job metadata are rejected", () => {
  equal(validJobMetadata(job), true);
  equal(validJobMetadata({ ...job, tombstoneSequence: Number(job.tombstoneSequence) as unknown as bigint }), false);
  equal(validJobMetadata({ ...job, generation: 0n }), false);
  equal(validJobMetadata({ ...job, generation: 9223372036854775808n }), false);
  equal(validJobMetadata({ ...job, leaseToken: "bad" }), false);
  equal(validJobMetadata({ ...job, leaseExpiresAt: "bad" }), false);
});
